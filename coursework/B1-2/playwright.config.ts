import { defineConfig } from "@playwright/test"

export default defineConfig({
  testDir: "./tests",
  testMatch: "**/*.spec.ts",
  outputDir: "./artifacts/test-results",
  reporter: [["line"], ["html", { outputFolder: "artifacts/playwright-report", open: "never" }]],
  retries: 0,
  workers: 1,
  use: {
    baseURL: process.env.BASE_URL ?? "http://127.0.0.1:8088",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "off",
  },
})
