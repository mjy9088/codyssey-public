import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { deploymentConfig } from "./request.mjs"

export async function provision(request, { runCLI, rulesPath }) {
  const config = deploymentConfig(request, rulesPath)
  if (request.mode === "plan") return config

  const scope = ["--project", request.project, "--non-interactive"]
  const response = JSON.parse(await runCLI(["apps:list", "WEB", ...scope, "--json"], true))
  if (response.status !== "success" || !Array.isArray(response.result)) {
    throw new Error("Unable to verify existing Firebase Web Apps; no deployment attempted")
  }
  if (
    !response.result.some(
      (app) => app?.platform === "WEB" && typeof app.appId === "string" && app.appId,
    )
  ) {
    throw new Error(
      "An existing Firebase Web App is required; no app will be created automatically",
    )
  }

  const directory = await mkdtemp(join(tmpdir(), "benchbook-firebase-"))
  try {
    const configPath = join(directory, "firebase.json")
    await writeFile(configPath, JSON.stringify(config), { mode: 0o600 })
    for (const target of ["auth", "firestore:rules"]) {
      await runCLI(["deploy", "--only", target, ...scope, "--config", configPath])
    }
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
  return config
}
