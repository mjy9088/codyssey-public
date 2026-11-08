import assert from "node:assert/strict"
import { access, readdir, readFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { provision } from "./provision.mjs"
import { deploymentConfig, parseRequest } from "./request.mjs"

const target = ["--project", "synthetic-demo", "--create-location", "asia-northeast3"]
const consent = ["--confirm-project", "synthetic-demo", "--accept-shared-demo-policy"]
const apply = () => parseRequest(["apply", ...target, ...consent])

test("offline plan needs explicit target and never assumes apply consent", () => {
  assert.deepEqual(parseRequest(["plan", ...target]), {
    mode: "plan",
    project: "synthetic-demo",
    createLocation: "asia-northeast3",
  })
  for (const args of [
    [],
    ["apply", ...target],
    ["apply", ...target, "--confirm-project", "another-project", consent[2]],
    ["plan", ...target, "--project", "another-project"],
    ["plan", "--project", "default", "--create-location", ""],
    ["plan", ...target, "--unknown"],
    ["plan", ...target, "--create-location", "nam5"],
    ["login", ...target],
    ["apply", ...target, ...consent, "--force"],
  ])
    assert.throws(() => parseRequest(args))
})

test("configuration only enables anonymous Auth and publishes default database rules", () => {
  assert.deepEqual(deploymentConfig(apply(), "/operator/firestore.rules"), {
    auth: { providers: { anonymous: true } },
    firestore: {
      database: "(default)",
      location: "asia-northeast3",
      edition: "standard",
      rules: "/operator/firestore.rules",
    },
  })
})

function fakeCLI({ failure, apps = [{ appId: "1:123:web:synthetic", platform: "WEB" }] } = {}) {
  const calls = []
  const configs = []
  const paths = []
  const runCLI = async (args, capture = false) => {
    calls.push(args)
    assert.equal(args[args.indexOf("--project") + 1], "synthetic-demo")
    assert.ok(args.includes("--non-interactive"))
    if (args[0] === "apps:list") {
      assert.equal(capture, true)
      assert.deepEqual(args, [
        "apps:list",
        "WEB",
        "--project",
        "synthetic-demo",
        "--non-interactive",
        "--json",
      ])
      return JSON.stringify({ status: "success", result: apps })
    }
    const configPath = args[args.indexOf("--config") + 1]
    paths.push(configPath)
    configs.push(JSON.parse(await readFile(configPath, "utf8")))
    const { stat } = await import("node:fs/promises")
    assert.equal((await stat(configPath)).mode & 0o777, 0o600)
    if (args.includes(failure)) throw new Error("Synthetic CLI failure")
    return ""
  }
  return { runCLI, calls, configs, paths }
}

test("repeat apply stays scoped and uses identical desired state without local checkpoints", async () => {
  const cli = fakeCLI()
  for (let i = 0; i < 2; i++) {
    await provision(apply(), { ...cli, rulesPath: "/operator/firestore.rules" })
  }
  assert.deepEqual(
    cli.calls.map((args) => args[0]),
    ["apps:list", "deploy", "deploy", "apps:list", "deploy", "deploy"],
  )
  assert.deepEqual(
    cli.calls
      .filter((args) => args[0] === "deploy")
      .map((args) => args[args.indexOf("--only") + 1]),
    ["auth", "firestore:rules", "auth", "firestore:rules"],
  )
  assert.ok(
    cli.configs.every((config) => JSON.stringify(config) === JSON.stringify(cli.configs[0])),
  )
  for (const path of cli.paths) await assert.rejects(access(path))
})

test("Auth failure prevents rules publication; Firestore failure is recoverable by rerun", async () => {
  for (const failure of ["auth", "firestore:rules"]) {
    const cli = fakeCLI({ failure })
    await assert.rejects(
      provision(apply(), { ...cli, rulesPath: "/operator/firestore.rules" }),
      /Synthetic CLI failure/,
    )
    assert.equal(cli.calls.length, failure === "auth" ? 2 : 3)
    for (const path of cli.paths) await assert.rejects(access(path))
    const recovery = fakeCLI()
    await provision(apply(), { ...recovery, rulesPath: "/operator/firestore.rules" })
    assert.equal(recovery.calls.length, 3)
  }
})

test("missing Web App or invalid preflight response fails before mutation", async () => {
  for (const apps of [[], [{ appId: "1:123:android:synthetic", platform: "ANDROID" }]]) {
    const cli = fakeCLI({ apps })
    await assert.rejects(
      provision(apply(), { ...cli, rulesPath: "/operator/firestore.rules" }),
      /existing Firebase Web App/,
    )
    assert.equal(cli.calls.length, 1)
  }
  for (const response of ["not JSON", '{"status":"error"}', '{"status":"success","result":{}}']) {
    let count = 0
    await assert.rejects(
      provision(apply(), {
        runCLI: async () => {
          count++
          return response
        },
        rulesPath: "/operator/firestore.rules",
      }),
    )
    assert.equal(count, 1)
  }
})

test("offline plan performs no CLI calls or temporary writes", async () => {
  const before = await readdir(tmpdir())
  const cli = fakeCLI()
  await provision(parseRequest(["plan", ...target]), {
    ...cli,
    rulesPath: join(tmpdir(), "unused.rules"),
  })
  assert.equal(cli.calls.length, 0)
  const after = await readdir(tmpdir())
  assert.deepEqual(
    after.filter((name) => name.startsWith("benchbook-firebase-")),
    before.filter((name) => name.startsWith("benchbook-firebase-")),
  )
})
