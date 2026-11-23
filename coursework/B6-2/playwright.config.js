import { defineConfig } from "@playwright/test"

const baseURL = process.env.BASE_URL ?? "http://127.0.0.1:8000"

export default defineConfig({
  testDir: "./tests-browser",
  outputDir: process.env.PLAYWRIGHT_OUTPUT_DIR ?? "/tmp/folio-playwright-results",
  reporter: "line",
  workers: 1,
  retries: 0,
  ...(process.env.COURSEWORK_NATIVE_BROWSER === "1"
    ? { webServer: { command: "just demo", url: baseURL } }
    : {}),
  use: {
    baseURL,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
})
