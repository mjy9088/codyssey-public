import { randomUUID } from "node:crypto"
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises"
import { createServer } from "node:net"
import { dirname, join, resolve } from "node:path"
import { setTimeout as delay } from "node:timers/promises"
import { fileURLToPath } from "node:url"
import {
  closeProcesses,
  redact,
  signalProcessGroup,
  startLoggedProcess,
} from "./native-processes.mjs"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..")
if (process.argv.length > 2) {
  console.log(
    "Usage: node scripts/verify-native.mjs\nRequires Node, Java 21+, installed app/operator locked dependencies, and Chromium.",
  )
  process.exit(process.argv.length === 3 && process.argv[2] === "--help" ? 0 : 2)
}
const output = join(root, "artifacts")
await mkdir(output, { recursive: true })
const run = await mkdtemp(join(output, "native-firebase-"))
const home = join(run, "home")
await mkdir(home, { mode: 0o700 })
const project = `demo-benchbook-${randomUUID().slice(0, 8)}`
const env = {
  PATH: process.env.PATH,
  ...(process.env.JAVA_HOME ? { JAVA_HOME: process.env.JAVA_HOME } : {}),
  ...(process.env.LD_LIBRARY_PATH ? { LD_LIBRARY_PATH: process.env.LD_LIBRARY_PATH } : {}),
  ...(process.env.FONTCONFIG_FILE ? { FONTCONFIG_FILE: process.env.FONTCONFIG_FILE } : {}),
  ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
    ? { PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH }
    : {}),
  HOME: home,
  XDG_CONFIG_HOME: join(home, "config"),
  XDG_CACHE_HOME: join(home, "cache"),
  FIREBASE_CLI_DISABLE_UPDATE_CHECK: "true",
  FIREBASE_CLI_DISABLE_USAGE_STATS: "true",
  FIREBASE_EMULATORS_PATH: join(output, "native-emulator-cache"),
  GOOGLE_APPLICATION_CREDENTIALS: join(home, "no-cloud-credentials.json"),
  GCLOUD_PROJECT: project,
  VITE_USE_EMULATORS: "true",
  VITE_FIREBASE_PROJECT_ID: project,
  VITE_FIREBASE_API_KEY: "synthetic-native-emulator-key",
  VITE_FIREBASE_AUTH_DOMAIN: `${project}.firebaseapp.com`,
  FIREBASE_TEST_PROJECT_ID: project,
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8085",
  FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
  BASE_URL: "http://127.0.0.1:4173",
  B12_NATIVE_VERIFICATION: "true",
}
const children = []
let interrupted = false
let passed = false
const start = (name, executable, args, cwd = root) => {
  const record = startLoggedProcess({
    executable,
    args,
    cwd,
    env,
    logPath: join(run, `${name}.log`),
  })
  children.push(record)
  return record
}
const execute = async (name, executable, args) => {
  const result = await start(name, executable, args).done
  if (result.code !== 0) throw new Error(`${name} failed; inspect ${join(run, `${name}.log`)}`)
}
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    interrupted = true
    for (const { child } of children) signalProcessGroup(child, "SIGINT")
  })
}
const waitFor = async (url, child, ready = async (response) => response.ok) => {
  for (let attempt = 0; attempt < 360; attempt++) {
    if (interrupted || child.exitCode !== null || child.signalCode !== null) {
      throw new Error("Verification service stopped before readiness")
    }
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(1000) })
      if (response.ok && (await ready(response))) return
    } catch (error) {
      if (!(error instanceof TypeError) && error.name !== "TimeoutError") throw error
    }
    await delay(500)
  }
  throw new Error(`Local service readiness timed out: ${url}`)
}
const assertPortsAvailable = async () => {
  for (const port of [4173, 4400, 4500, 8085, 9099, 9150]) {
    await new Promise((resolvePort, reject) => {
      const server = createServer()
      server.once("error", reject)
      server.listen(port, "127.0.0.1", () => server.close(resolvePort))
    })
  }
}
const cleanup = async () => {
  await closeProcesses(children)
  for (let attempt = 0; ; attempt++) {
    try {
      await assertPortsAvailable()
      break
    } catch (error) {
      if (error.code !== "EADDRINUSE" || attempt >= 60) throw error
      await delay(50)
    }
  }
  for (const name of ["firestore-debug.log", "firebase-debug.log"]) {
    const path = join(run, name)
    try {
      await writeFile(path, redact(await readFile(path, "utf8")))
    } catch (error) {
      if (error.code !== "ENOENT") throw error
    }
  }
}
try {
  await assertPortsAvailable()
  console.log(`Native Firebase verification: ${run}`)
  await execute("java-version", "java", ["-version"])
  const javaVersion = await readFile(join(run, "java-version.log"), "utf8")
  if (Number(javaVersion.match(/version "(\d+)/)?.[1] ?? 0) < 21) {
    throw new Error("Native verification requires Java 21 or later")
  }
  const cli = join(root, "ops/firebase/node_modules/firebase-tools/lib/bin/firebase.js")
  await execute("firebase-version", process.execPath, [cli, "--version"])
  const expectedCLI = JSON.parse(await readFile(join(root, "ops/firebase/package.json"), "utf8"))
  if (
    (await readFile(join(run, "firebase-version.log"), "utf8")).trim() !==
    expectedCLI.dependencies["firebase-tools"]
  ) {
    throw new Error("Native Firebase CLI differs from its pinned operator dependency")
  }
  const config = join(run, "firebase.json")
  await writeFile(
    config,
    JSON.stringify({
      firestore: { rules: join(root, "firestore.rules") },
      emulators: {
        auth: { host: "127.0.0.1", port: 9099 },
        firestore: { host: "127.0.0.1", port: 8085 },
        hub: { host: "127.0.0.1", port: 4400 },
        logging: { host: "127.0.0.1", port: 4500 },
        ui: { enabled: false },
        singleProjectMode: true,
      },
    }),
  )
  const firebase = start(
    "firebase",
    process.execPath,
    [
      cli,
      "emulators:start",
      "--config",
      config,
      "--only",
      "auth,firestore",
      "--project",
      project,
      "--non-interactive",
    ],
    run,
  )
  await waitFor("http://127.0.0.1:4400/emulators", firebase.child, async (response) => {
    const services = await response.json()
    return Boolean(services.auth && services.firestore)
  })
  await execute("build", "npm", ["run", "build", "--", "--outDir", join(run, "site")])
  const web = start("web", process.execPath, [
    join(root, "node_modules/vite/bin/vite.js"),
    "preview",
    "--host",
    "127.0.0.1",
    "--port",
    "4173",
    "--strictPort",
    "--outDir",
    join(run, "site"),
  ])
  await waitFor(env.BASE_URL, web.child)
  await execute("browser", process.execPath, [
    join(root, "node_modules/@playwright/test/cli.js"),
    "test",
    "--output",
    join(run, "test-results"),
    "--reporter",
    "line",
  ])
  console.log("PASS: real local Auth/Firestore, checked-in rules, production-build browser suite")
  const isolation = await start("owner-isolation", process.execPath, [
    join(root, "tests/emulator-isolation-probe.mjs"),
  ]).done
  if (isolation.code === 2) {
    console.log("FAIL: owner isolation; checked-in shared-demo policy permits cross-user access")
    process.exitCode = 2
  } else if (isolation.code !== 0) throw new Error("Owner isolation probe failed unexpectedly")
  passed = true
} catch (error) {
  console.error(error instanceof Error ? error.message : "Native verification failed")
  process.exitCode = interrupted ? 130 : 1
} finally {
  await cleanup()
  console.log(`Evidence (ignored): ${run}`)
  process.exitCode = interrupted ? 130 : passed ? (process.exitCode ?? 0) : 1
}
