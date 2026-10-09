import { defineConfig, devices } from "@playwright/test";

const { BASE_URL: configuredBaseURL } = process.env;
const baseURL = configuredBaseURL ?? "http://127.0.0.1:8000";

export default defineConfig({
  testDir: "./tests-browser",
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  workers: 1,
  reporter: "line",
  outputDir: "/tmp/playwright-results",
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
