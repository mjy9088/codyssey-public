import { afterEach, expect, test, vi } from "vitest"

afterEach(() => {
  vi.unstubAllEnvs()
  vi.resetModules()
})

test("accepts the isolated native demo project and loopback emulator ports", async () => {
  vi.stubEnv("FIREBASE_TEST_PROJECT_ID", "demo-native-verification")
  vi.stubEnv("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8085")
  vi.stubEnv("FIREBASE_AUTH_EMULATOR_HOST", "127.0.0.1:9099")
  const endpoints = await import("./emulator-endpoints")
  expect(endpoints.resetDocumentsUrl).toBe(
    "http://127.0.0.1:8085/emulator/v1/projects/demo-native-verification/databases/(default)/documents",
  )
  expect(endpoints.authOrigin).toBe("http://127.0.0.1:9099")
})

test.each([
  ["FIREBASE_TEST_PROJECT_ID", "real-cloud-project"],
  ["FIRESTORE_EMULATOR_HOST", "firestore.googleapis.com:443"],
  ["FIRESTORE_EMULATOR_HOST", "127.0.0.1:8085/another-path"],
  ["FIREBASE_AUTH_EMULATOR_HOST", "synthetic:credential@localhost:9099"],
])("rejects unsafe emulator administration setting %s", async (name, value) => {
  vi.stubEnv(name, value)
  await expect(import("./emulator-endpoints")).rejects.toThrow()
})
