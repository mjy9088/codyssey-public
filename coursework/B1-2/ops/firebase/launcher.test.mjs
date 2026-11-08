import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { delimiter, join } from "node:path"
import { test } from "node:test"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("../../", import.meta.url))
const script = join(root, "scripts/firebase-live.sh")
const target = ["--project", "synthetic-demo", "--create-location", "nam5"]

test("launcher isolates offline commands, limits credential mounts, and rejects checkout credentials", async () => {
  const directory = await mkdtemp(join(tmpdir(), "benchbook-operator-test-"))
  try {
    const bin = join(directory, "bin")
    const credentials = join(directory, "private credentials")
    const record = join(directory, "docker-args.json")
    await mkdir(bin)
    await mkdir(credentials, { mode: 0o700 })
    await writeFile(
      join(bin, "docker"),
      `#!/usr/bin/env node
import { writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
writeFileSync(process.env.OPERATOR_TEST_ARGS, JSON.stringify(args) + '\\n', {flag:'a'});
if (args[0] === 'build' && args.includes('--quiet')) console.log('sha256:synthetic-current-image');
`,
      { mode: 0o700 },
    )
    const env = {
      ...process.env,
      PATH: `${bin}${delimiter}${process.env.PATH}`,
      OPERATOR_TEST_ARGS: record,
      BENCHBOOK_FIREBASE_CREDENTIALS: credentials,
    }
    const run = (args, overrides = {}) =>
      spawnSync("sh", [script, ...args], {
        env: { ...env, ...overrides },
        encoding: "utf8",
      })
    assert.equal(run(["plan", ...target]).status, 0)
    let args = JSON.parse((await readFile(record, "utf8")).trim())
    assert.ok(args.includes("none"))
    assert.ok(!args.some((arg) => arg.includes("target=/credentials")))
    assert.ok(args.some((arg) => arg.includes("firestore.rules,readonly")))
    assert.ok(!args.includes("-e"))

    const apply = [
      "apply",
      ...target,
      "--confirm-project",
      "synthetic-demo",
      "--accept-shared-demo-policy",
    ]
    await rm(record)
    assert.equal(run(apply).status, 0)
    const calls = (await readFile(record, "utf8"))
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line))
    assert.equal(calls.length, 2)
    assert.equal(calls[0][0], "build")
    assert.ok(calls[0].includes("--quiet"))
    args = calls[1]
    assert.deepEqual(args.slice(-apply.length), apply)
    assert.ok(args.includes(`type=bind,source=${credentials},target=/credentials`))
    assert.ok(!args.includes("-it"))
    assert.ok(!args.includes("--privileged"))
    assert.ok(args.includes("sha256:synthetic-current-image"))
    assert.ok(args.includes(`benchbook-firebase-operator-${process.getuid()}`))
    assert.ok(!args.some((arg) => arg.includes("docker.sock")))

    await rm(record)
    for (const [args, overrides] of [
      [["unknown"], {}],
      [["build", "extra"], {}],
      [["login", "extra"], {}],
      [apply, { BENCHBOOK_FIREBASE_CREDENTIALS: root }],
      [apply, { BENCHBOOK_FIREBASE_CREDENTIALS: "/" }],
      [apply, { BENCHBOOK_FIREBASE_CREDENTIALS: "relative" }],
      [apply, { BENCHBOOK_FIREBASE_CREDENTIALS: "" }],
    ]) {
      assert.notEqual(run(args, overrides).status, 0)
      await assert.rejects(readFile(record))
    }
    assert.equal(run(["--help"]).status, 0)
    await assert.rejects(readFile(record))
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})
