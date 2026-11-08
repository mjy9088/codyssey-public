import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { access, chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { test } from "node:test"
import { fileURLToPath } from "node:url"
import { cliVersion } from "./request.mjs"

const source = dirname(fileURLToPath(import.meta.url))
const args = [
  "apply",
  "--project",
  "synthetic-demo",
  "--create-location",
  "nam5",
  "--confirm-project",
  "synthetic-demo",
  "--accept-shared-demo-policy",
]

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "benchbook-runtime-test-"))
  const operator = join(directory, "ops/firebase")
  const credentials = join(directory, "credentials")
  const record = join(directory, "calls.jsonl")
  await mkdir(join(operator, "node_modules/.bin"), { recursive: true })
  await mkdir(join(credentials, "configstore"), { recursive: true, mode: 0o700 })
  await writeFile(
    join(credentials, "configstore/firebase-tools.json"),
    JSON.stringify({
      user: { email: "operator@example.invalid" },
      tokens: { refresh_token: "synthetic-not-a-real-token" },
    }),
  )
  for (const file of ["main.mjs", "request.mjs", "provision.mjs", "credentials.mjs"]) {
    await writeFile(join(operator, file), await readFile(join(source, file)))
  }
  await writeFile(join(directory, "firestore.rules"), "synthetic rules input")
  await writeFile(
    join(operator, "node_modules/.bin/firebase"),
    `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
if (args[0] === '--version') { console.log('${cliVersion}'); process.exit(0); }
fs.appendFileSync(process.env.OPERATOR_TEST_RECORD, JSON.stringify(args) + '\\n');
if (args[0] === 'logout') {
  if (!process.env.OPERATOR_TEST_LOGOUT_REMAINS) {
    fs.writeFileSync(process.env.XDG_CONFIG_HOME + '/configstore/firebase-tools.json', '{}');
  }
  process.exit(0);
}
if (args[0] === 'apps:list') {
  console.log(JSON.stringify({status:'success',result:[{appId:'1:123:web:synthetic',platform:'WEB'}]}));
  process.exit(0);
}
const configPath = args[args.indexOf('--config') + 1];
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
fs.accessSync(config.firestore.rules);
if (process.env.OPERATOR_TEST_SIGNAL) {
  process.kill(process.ppid, process.env.OPERATOR_TEST_SIGNAL);
  setTimeout(() => process.exit(90), 5000);
} else if (args.includes(process.env.OPERATOR_TEST_FAILURE)) process.exit(7);
`,
    { mode: 0o700 },
  )
  const run = (command, overrides = {}) =>
    spawnSync(process.execPath, [join(operator, "main.mjs"), ...command], {
      env: {
        ...process.env,
        XDG_CONFIG_HOME: credentials,
        OPERATOR_TEST_RECORD: record,
        ...overrides,
      },
      encoding: "utf8",
      timeout: 15000,
    })
  const calls = async () =>
    (await readFile(record, "utf8"))
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line))
  return { directory, operator, credentials, record, run, calls }
}

test("actual operator process rejects missing/private credentials before calling Firebase", async () => {
  const f = await fixture()
  try {
    await rm(join(f.credentials, "configstore/firebase-tools.json"))
    const missing = f.run(args)
    assert.equal(missing.status, 1)
    assert.match(missing.stderr, /login missing/)
    await assert.rejects(access(f.record))
    await chmod(f.directory, 0o755)
    const unsafe = f.run(args, { XDG_CONFIG_HOME: f.directory })
    assert.equal(unsafe.status, 1)
    assert.match(unsafe.stderr, /0700/)
    await assert.rejects(access(f.record))
    const invalid = f.run(["apply", "--project", "synthetic-demo", "--create-location", "nam5"])
    assert.equal(invalid.status, 1)
    assert.match(invalid.stderr, /confirm-project/)
  } finally {
    await rm(f.directory, { recursive: true, force: true })
  }
})

test("empty, malformed, and access-only logins cannot fall back to ambient credentials", async () => {
  const f = await fixture()
  try {
    for (const login of [
      "{}",
      "null",
      "{secret-token",
      JSON.stringify({
        user: { email: "operator@example.invalid" },
        tokens: { access_token: "synthetic-access-only" },
      }),
      JSON.stringify({ user: { email: "" }, tokens: { refresh_token: "synthetic" } }),
    ]) {
      await writeFile(join(f.credentials, "configstore/firebase-tools.json"), login)
      const result = f.run(args)
      assert.equal(result.status, 1)
      assert.ok(!result.stderr.includes("secret-token"))
      assert.ok(!result.stderr.includes("synthetic-access-only"))
      await assert.rejects(access(f.record))
    }
    for (const mode of [0o500, 0o600, 0o750]) {
      await chmod(f.credentials, mode)
      const result = f.run(args)
      assert.equal(result.status, 1)
      assert.match(result.stderr, /0700/)
      await assert.rejects(access(f.record))
    }
  } finally {
    await chmod(f.credentials, 0o700)
    await rm(f.directory, { recursive: true, force: true })
  }
})

test("logout verifies local credential removal without claiming remote revocation", async () => {
  for (const remains of ["", "true"]) {
    const f = await fixture()
    try {
      const result = f.run(["logout"], { OPERATOR_TEST_LOGOUT_REMAINS: remains })
      assert.equal(result.status, remains ? 1 : 0)
      if (remains) assert.match(result.stderr, /Local login remains/)
      else assert.match(result.stdout, /not guaranteed/)
    } finally {
      await rm(f.directory, { recursive: true, force: true })
    }
  }
})

test("actual operator process applies both targets and stops on CLI failures", async () => {
  for (const failure of ["", "auth", "firestore:rules"]) {
    const f = await fixture()
    try {
      const result = f.run(args, { OPERATOR_TEST_FAILURE: failure })
      assert.equal(result.status, failure ? 1 : 0, result.stderr)
      const calls = await f.calls()
      assert.equal(calls.length, failure === "auth" ? 2 : 3)
      for (const call of calls.filter((call) => call[0] === "deploy")) {
        await assert.rejects(access(call[call.indexOf("--config") + 1]))
      }
      if (!failure) assert.match(result.stdout, /CLI deployment completed/)
      else assert.match(result.stderr, /setup is incomplete/)
    } finally {
      await rm(f.directory, { recursive: true, force: true })
    }
  }
})

test("actual SIGINT and SIGTERM stop before rules, preserve exit status and remove temporary config", async () => {
  for (const [signal, expected] of [
    ["SIGINT", 130],
    ["SIGTERM", 143],
  ]) {
    const f = await fixture()
    try {
      const result = f.run(args, { OPERATOR_TEST_SIGNAL: signal })
      assert.equal(result.status, expected, result.stderr)
      assert.match(result.stderr, /Interrupted/)
      const calls = await f.calls()
      assert.equal(calls.length, 2)
      const deploy = calls[1]
      await assert.rejects(access(deploy[deploy.indexOf("--config") + 1]))
    } finally {
      await rm(f.directory, { recursive: true, force: true })
    }
  }
})
