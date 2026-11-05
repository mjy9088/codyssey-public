import assert from "node:assert/strict"
import { once } from "node:events"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import net from "node:net"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import {
  closeProcesses,
  signalProcessGroup,
  startLoggedProcess,
} from "../scripts/native-processes.mjs"

const listening = (port) =>
  new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port })
    socket.once("connect", () => {
      socket.destroy()
      resolve(true)
    })
    socket.once("error", () => resolve(false))
  })

test("cleanup signals a surviving descendant even after the group leader exits", async (t) => {
  const folder = await mkdtemp(join(tmpdir(), "native-descendant-test-"))
  const record = startLoggedProcess({
    executable: process.execPath,
    args: [
      "-e",
      `
    const child = require('node:child_process').spawn(process.execPath, ['-e',
      "const s=require('node:net').createServer();s.listen(0,'127.0.0.1',()=>process.send(s.address().port))"
    ], {stdio:['ignore','ignore','ignore','ipc']});
    child.once('message', port => { process.stdout.write(String(port)+'\\n',()=>process.exit(0)); });
  `,
    ],
    cwd: folder,
    env: {},
    logPath: join(folder, "leader.log"),
  })
  const leader = record.child
  t.after(async () => {
    try {
      process.kill(-leader.pid, "SIGKILL")
    } catch (error) {
      if (error.code !== "ESRCH") throw error
    }
    await rm(folder, { recursive: true, force: true })
  })
  const [chunk] = await once(leader.stdout, "data")
  const port = Number(chunk.toString().trim())
  await record.done
  assert.equal(await listening(port), true)
  await closeProcesses([record])
  for (let attempt = 0; attempt < 100 && (await listening(port)); attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 10))
  }
  assert.equal(await listening(port), false)
})

test("logs redact a JWT split over child stdout chunks and retain exit two", async () => {
  const folder = await mkdtemp(join(tmpdir(), "native-log-test-"))
  const logPath = join(folder, "child.log")
  try {
    const record = startLoggedProcess({
      executable: process.execPath,
      args: [
        "-e",
        "process.stdout.write('eyJhbGciOiJub25lIn0.');setTimeout(()=>{process.stdout.write('c3ludGhldGlj.c2lnbmF0dXJl');process.exit(2)},20)",
      ],
      cwd: folder,
      env: {},
      logPath,
    })
    assert.equal((await record.done).code, 2)
    assert.equal(await readFile(logPath, "utf8"), "[JWT REDACTED]")
    await closeProcesses([record])
  } finally {
    await rm(folder, { recursive: true, force: true })
  }
})

for (const signal of ["SIGINT", "SIGTERM"]) {
  test(`${signal} terminates an owned group and closes its log`, async (t) => {
    const folder = await mkdtemp(join(tmpdir(), "native-signal-test-"))
    const record = startLoggedProcess({
      executable: process.execPath,
      args: ["-e", "process.stdout.write('ready\\n');setInterval(()=>{},1000)"],
      cwd: folder,
      env: {},
      logPath: join(folder, "child.log"),
    })
    t.after(async () => {
      await closeProcesses([record])
      await rm(folder, { recursive: true, force: true })
    })
    await once(record.child.stdout, "data")
    signalProcessGroup(record.child, signal)
    assert.equal((await record.done).signal, signal)
    assert.equal(await readFile(join(folder, "child.log"), "utf8"), "ready\n")
  })
}

test("a log write failure cannot be reported as successful execution", async (t) => {
  const folder = await mkdtemp(join(tmpdir(), "native-failure-test-"))
  const record = startLoggedProcess({
    executable: process.execPath,
    args: ["--version"],
    cwd: folder,
    env: {},
    logPath: folder,
  })
  t.after(async () => {
    signalProcessGroup(record.child, "SIGKILL")
    await rm(folder, { recursive: true, force: true })
  })
  await assert.rejects(
    closeProcesses([record]),
    (error) =>
      error instanceof AggregateError && error.errors.some((entry) => entry.code === "EISDIR"),
  )
})

test("an early service spawn failure is retained until cleanup observes it", async (t) => {
  const folder = await mkdtemp(join(tmpdir(), "native-spawn-test-"))
  const record = startLoggedProcess({
    executable: join(folder, "missing-executable"),
    args: [],
    cwd: folder,
    env: {},
    logPath: join(folder, "service.log"),
  })
  t.after(async () => {
    await rm(folder, { recursive: true, force: true })
  })
  await record.settled
  await assert.rejects(
    closeProcesses([record]),
    (error) =>
      error instanceof AggregateError && error.errors.some((entry) => entry.code === "ENOENT"),
  )
})
