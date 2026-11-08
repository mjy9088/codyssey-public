import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"
import {
  requireCredentialDirectory,
  requireLoggedOut,
  requireOperatorLogin,
} from "./credentials.mjs"
import { provision } from "./provision.mjs"
import { cliVersion, help, parseRequest } from "./request.mjs"

const binary = fileURLToPath(new URL("./node_modules/.bin/firebase", import.meta.url))
const rulesPath = fileURLToPath(new URL("../../firestore.rules", import.meta.url))
const controller = new AbortController()
let interrupted = 0
for (const [signal, status] of [
  ["SIGINT", 130],
  ["SIGTERM", 143],
]) {
  process.on(signal, () => {
    interrupted = status
    process.exitCode = status
    controller.abort()
  })
}

function runCLI(args, capture = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, {
      cwd: "/tmp",
      stdio: ["inherit", capture ? "pipe" : "inherit", "inherit"],
      signal: controller.signal,
    })
    let output = ""
    child.stdout?.setEncoding("utf8")
    child.stdout?.on("data", (chunk) => {
      output += chunk
    })
    // Abort sends SIGTERM to the CLI. Wait for close before temporary config cleanup.
    let failure
    child.on("error", (error) => {
      failure = error
    })
    child.on("close", (code, signal) => {
      if (failure) reject(failure)
      else if (code !== 0)
        reject(new Error(`Firebase CLI ${args[0]} failed (${signal ?? code}); setup is incomplete`))
      else resolve(output.trim())
    })
  })
}

async function main() {
  const args = process.argv.slice(2)
  const [mode] = args
  if (args.length === 1 && ["--help", "help"].includes(mode)) {
    console.log(help)
    return
  }
  if (["login", "logout", "version"].includes(mode)) {
    if (args.length !== 1) throw new Error(`${mode} accepts no options`)
    if (mode !== "version") await requireCredentialDirectory(process.env.XDG_CONFIG_HOME)
    const version = await runCLI(["--version"], true)
    if (version !== cliVersion)
      throw new Error(`Expected Firebase CLI ${cliVersion}; rebuild operator image`)
    if (mode === "version") console.log(`Firebase CLI ${version}`)
    else {
      await runCLI(mode === "login" ? ["login", "--no-localhost"] : ["logout"])
      if (mode === "logout") {
        await requireLoggedOut(process.env.XDG_CONFIG_HOME)
        console.log(
          "Local login removed. Remote revocation was attempted, not guaranteed; inspect CLI warnings.",
        )
      }
    }
    return
  }
  const request = parseRequest(args)
  if (request.mode === "plan") {
    console.log("OFFLINE PLAN: no remote state inspected; not a cloud diff or readiness check.")
    console.log(
      `Project: ${request.project}; creation-only Firestore location: ${request.createLocation}`,
    )
    console.log("Existing database location is retained even if different. No migration.")
    console.log("Apply will verify a Web App exists, deploy Auth, then deploy Firestore rules.")
    console.log(
      "May enable APIs/create (default). Replaces current rules with shared signed-in CRUD.",
    )
    console.log("No billing changes requested. Existing billing/costs are NOT inspected or capped.")
    console.log(JSON.stringify(await provision(request, { runCLI, rulesPath }), null, 2))
    return
  }
  await requireCredentialDirectory(process.env.XDG_CONFIG_HOME)
  await requireOperatorLogin(process.env.XDG_CONFIG_HOME)
  if ((await runCLI(["--version"], true)) !== cliVersion) {
    throw new Error(`Expected Firebase CLI ${cliVersion}; rebuild operator image`)
  }
  console.log(`Applying shared-demo configuration to ${request.project}. Billing is not inspected.`)
  console.log(
    `Firestore creation-only location: ${request.createLocation}; existing location is retained.`,
  )
  await provision(request, { runCLI, rulesPath })
  console.log(
    "CLI deployment completed. Verify the actual frontend's Auth and durable CRUD separately.",
  )
}

try {
  await main()
} catch (error) {
  console.error(
    interrupted
      ? "Interrupted; remote operations may have completed. Rerun to converge."
      : error instanceof Error
        ? error.message
        : "Operator command failed",
  )
  process.exitCode = interrupted || 1
}
