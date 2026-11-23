import { defineConfig } from "@playwright/test";

const verificationMode = process.env.VERIFY_MODE ?? "docker";
if (!["native", "docker", "vm"].includes(verificationMode)) {
  throw new Error(`Unknown portfolio verification mode: ${verificationMode}`);
}
const native = verificationMode === "native";
const referenceScreenshots = "**/reference-screenshots.spec.mjs";
const baseURL = native ? "http://127.0.0.1:8000" : process.env.BASE_URL || "http://127.0.0.1:8080";

export default defineConfig({
  testDir: "./tests",
  testMatch: "**/*.spec.mjs",
  ...(native ? { testIgnore: referenceScreenshots } : {}),
  metadata: { verificationMode },
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
  ...(native ? { webServer: { command: "just demo", url: baseURL } } : {}),
  use: {
    baseURL,
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
    {
      name: "tablet",
      testIgnore: referenceScreenshots,
      use: { viewport: { width: 768, height: 1024 }, colorScheme: "light" },
    },
    { name: "dark", use: { viewport: { width: 1280, height: 900 }, colorScheme: "dark" } },
  ],
});
