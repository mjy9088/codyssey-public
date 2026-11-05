import { spawn } from "node:child_process"
import { writeFile } from "node:fs/promises"
import { setTimeout as delay } from "node:timers/promises"

export const redact = (text) =>
  text.replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[JWT REDACTED]")

export function startLoggedProcess({ executable, args, cwd, env, logPath }) {
  const child = spawn(executable, args, {
    cwd,
    env,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
  })
  const chunks = []
  for (const stream of [child.stdout, child.stderr]) {
    stream.setEncoding("utf8")
    stream.on("data", (data) => chunks.push(data))
  }
  let spawnFailure
  const done = new Promise((resolve, reject) => {
    child.once("error", (error) => {
      spawnFailure = error
    })
    child.once("close", (code, signal) => {
      writeFile(logPath, redact(chunks.join(""))).then(() => {
        if (spawnFailure) reject(spawnFailure)
        else resolve({ code, signal })
      }, reject)
    })
  })
  return { child, done, settled: Promise.allSettled([done]) }
}

export function signalProcessGroup(child, signal) {
  if (child.pid) {
    try {
      process.kill(-child.pid, signal)
    } catch (error) {
      if (error.code !== "ESRCH") throw error
    }
  }
}

export async function closeProcesses(records) {
  for (const { child } of records) signalProcessGroup(child, "SIGINT")
  const closed = Promise.all(records.map(({ settled }) => settled)).then((results) =>
    results.flat(),
  )
  const controller = new AbortController()
  try {
    await Promise.race([closed, delay(2000, undefined, { signal: controller.signal })])
  } finally {
    controller.abort()
  }
  for (const { child } of records) signalProcessGroup(child, "SIGKILL")
  let timer
  let results
  try {
    results = await Promise.race([
      closed,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("Native child/log closure timed out")), 5000)
      }),
    ])
  } finally {
    clearTimeout(timer)
  }
  const failures = results.filter((result) => result.status === "rejected")
  if (failures.length) {
    throw new AggregateError(
      failures.map((result) => result.reason),
      "Native process/log cleanup failed",
    )
  }
}
