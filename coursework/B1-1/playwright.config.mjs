import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  workers: 1,
  timeout: 25_000,
  expect: { timeout: 5_000 },
  outputDir: "artifacts/test-results",
  snapshotPathTemplate: "{testDir}/../docs/screenshots/{arg}{ext}",
  updateSnapshots: "none",
  reporter: [["list"], ["json", { outputFile: "artifacts/results.json" }]],
  use: {
    baseURL: process.env.BASE_URL || "http://127.0.0.1:8080",
    browserName: "chromium",
    locale: "en-US",
    timezoneId: "UTC",
    contextOptions: { reducedMotion: "reduce", deviceScaleFactor: 1 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "desktop", use: { viewport: { width: 1280, height: 900 }, colorScheme: "light" } },
    { name: "mobile", use: { viewport: { width: 375, height: 812 }, colorScheme: "light" } },
    { name: "tablet", use: { viewport: { width: 768, height: 1024 }, colorScheme: "light" } },
    { name: "dark", use: { viewport: { width: 1280, height: 900 }, colorScheme: "dark" } },
  ],
});
