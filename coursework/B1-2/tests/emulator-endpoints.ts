import { z } from "zod"

const {
  FIREBASE_TEST_PROJECT_ID: project,
  FIRESTORE_EMULATOR_HOST: firestoreAddress,
  FIREBASE_AUTH_EMULATOR_HOST: authAddress,
} = process.env

export const emulatorProjectId = z
  .string()
  .regex(/^(benchbook-local|demo-[a-z0-9-]+)$/)
  .parse(project ?? "benchbook-local")

const endpoint = (value: string) => {
  const url = new URL(`http://${value}`)
  if (
    !["firebase", "127.0.0.1", "localhost"].includes(url.hostname) ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash
  ) {
    throw new Error("Verification endpoints must name a local Firebase emulator")
  }
  return url
}

const firestore = endpoint(firestoreAddress ?? "firebase:8080")
const auth = endpoint(authAddress ?? "firebase:9099")
export const firestoreOrigin = firestore.origin
export const authOrigin = auth.origin
export const firestoreHost = firestore.hostname
export const firestorePort = Number(firestore.port || 80)
export const documentsUrl = `${firestoreOrigin}/v1/projects/${emulatorProjectId}/databases/(default)/documents`
export const resetDocumentsUrl = `${firestoreOrigin}/emulator/v1/projects/${emulatorProjectId}/databases/(default)/documents`
export const rulesUrl = `${firestoreOrigin}/emulator/v1/projects/${emulatorProjectId}:securityRules`
