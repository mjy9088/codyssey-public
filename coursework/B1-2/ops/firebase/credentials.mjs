import { constants } from "node:fs"
import { access, readFile, stat } from "node:fs/promises"
import { join } from "node:path"

export async function requireCredentialDirectory(folder) {
  if (!folder) throw new Error("Dedicated operator credentials are required")
  const info = await stat(folder)
  if (!info.isDirectory() || (info.mode & 0o777) !== 0o700 || info.uid !== process.getuid()) {
    throw new Error("Credential directory must be owned by the current user with mode 0700")
  }
  await access(folder, constants.R_OK | constants.W_OK | constants.X_OK)
}

async function readLogin(folder) {
  let text
  try {
    text = await readFile(join(folder, "configstore/firebase-tools.json"), "utf8")
  } catch (error) {
    if (error?.code === "ENOENT") return undefined
    throw error
  }
  try {
    return JSON.parse(text)
  } catch {
    // JSON parser errors may quote secret-bearing input. Never expose that input.
    throw new Error("Malformed operator login; run firebase-live.sh login again")
  }
}

export async function requireOperatorLogin(folder) {
  const login = await readLogin(folder)
  if (
    typeof login?.user?.email !== "string" ||
    !login.user.email.trim() ||
    typeof login?.tokens?.refresh_token !== "string" ||
    !login.tokens.refresh_token.trim()
  ) {
    throw new Error("Operator login missing; run firebase-live.sh login first")
  }
}

export async function requireLoggedOut(folder) {
  const login = await readLogin(folder)
  if (
    login?.user ||
    login?.tokens ||
    (Array.isArray(login?.additionalAccounts) && login.additionalAccounts.length > 0)
  ) {
    throw new Error("Local login remains after logout; inspect the dedicated credential directory")
  }
}
