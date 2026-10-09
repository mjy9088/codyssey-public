import { defineConfig } from "@playwright/test"

export default defineConfig({
  testDir: "./tests-browser",
  outputDir: process.env.PLAYWRIGHT_OUTPUT_DIR ?? "/tmp/folio-playwright-results",
  reporter: "line",
  workers: 1,
  retries: 0,
  use: {
    baseURL: process.env.BASE_URL ?? "http://127.0.0.1:8000",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
})
