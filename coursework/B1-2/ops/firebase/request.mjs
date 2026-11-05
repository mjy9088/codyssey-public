export const cliVersion = "15.35.0"

export const help = `Usage: sh scripts/firebase-live.sh COMMAND [OPTIONS]

Commands:
  build       Build the pinned, separate operator image (requires internet)
  version     Print the installed Firebase CLI version (offline)
  login       Authenticate interactively using a browser on your own machine
  logout      Remove the local CLI login and attempt remote token revocation
  plan        Print an OFFLINE intended-operation preview, not a cloud diff
  apply       Enable Anonymous, then publish the checked-in Firestore rules

plan/apply options (all values explicit; Firebase project aliases are not used):
  --project ID                  Existing, dedicated disposable Firebase project
  --create-location LOCATION    Firestore location ONLY if (default) is absent
apply additionally requires:
  --confirm-project ID          Must exactly match --project
  --accept-shared-demo-policy   Accept replacing rules: any signed-in user can
                               read/edit/delete every workshop. Synthetic data
                               only. Billing is NOT inspected; existing billed
                               projects can incur charges. No spending cap.

Existing databases and their locations are preserved, not migrated. API enablement
and default database creation may occur during apply. No billing, project creation,
IAM, indexes, seeds, or authorized-domain changes are requested. Requires an existing
Firebase Web App and operator permissions. Never run concurrent applies per project.

login/logout/apply require a dedicated mode-0700 host directory outside the checkout:
  BENCHBOOK_FIREBASE_CREDENTIALS=/absolute/path
Only those commands mount it. Credentials never enter the lab, image, or frontend.
See docs/FIREBASE_PROVISIONING.md for setup, recovery, and live-verification limits.`

export function parseRequest(args) {
  const [mode, ...rest] = args
  if (mode !== "plan" && mode !== "apply") throw new Error("Expected plan or apply")
  const options = new Map()
  for (let i = 0; i < rest.length; i++) {
    const key = rest[i]
    if (
      ![
        "--project",
        "--create-location",
        "--confirm-project",
        "--accept-shared-demo-policy",
      ].includes(key)
    ) {
      throw new Error(`Unknown option: ${key}`)
    }
    if (options.has(key)) throw new Error(`Duplicate option: ${key}`)
    if (key === "--accept-shared-demo-policy") options.set(key, true)
    else {
      const value = rest[++i]
      if (!value || value.startsWith("--")) throw new Error(`Missing value for ${key}`)
      options.set(key, value)
    }
  }
  const project = options.get("--project")
  const createLocation = options.get("--create-location")
  if (typeof project !== "string" || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(project)) {
    throw new Error("--project must be an explicit Google Cloud project ID (6–30 characters)")
  }
  if (typeof createLocation !== "string" || !/^[a-z][a-z0-9-]{1,62}$/.test(createLocation)) {
    throw new Error("--create-location must be an explicit Firestore location ID")
  }
  const confirmed = options.get("--confirm-project")
  const accepted = options.get("--accept-shared-demo-policy")
  if (mode === "apply" && (confirmed !== project || accepted !== true)) {
    throw new Error("apply requires matching --confirm-project and --accept-shared-demo-policy")
  }
  if (mode === "plan" && (confirmed !== undefined || accepted !== undefined)) {
    throw new Error("Consent options belong to apply, not the offline plan")
  }
  return { mode, project, createLocation }
}

export function deploymentConfig(request, rulesPath) {
  return {
    auth: { providers: { anonymous: true } },
    firestore: {
      database: "(default)",
      location: request.createLocation,
      edition: "standard",
      rules: rulesPath,
    },
  }
}
