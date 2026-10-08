import { test, expect, API, repositories } from "./fixtures.mjs";

test("loading transitions to projects and language filtering", async ({ page }) => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  await page.route(API, async (route) => { await gate; await route.fulfill({ json: repositories }); });
  await page.goto("/");
  await expect(page.locator("#projects-status")).toContainText("Loading");
  await expect(page.locator("#project-list")).toHaveAttribute("aria-busy", "true");
  release();
  await expect(page.locator(".project-card")).toHaveCount(3);
  await page.locator("#project-filter").selectOption("JavaScript");
  await expect(page.locator(".project-card")).toHaveCount(1);
  await expect(page.locator(".project-name")).toHaveText("field-notes");
  await page.locator("#project-filter").selectOption("all");
  await expect(page.locator(".project-card")).toHaveCount(3);
});

test("empty API response has a distinct non-error state", async ({ page }) => {
  await page.route(API, (route) => route.fulfill({ json: [] }));
  await page.goto("/");
  await expect(page.locator("#projects-status")).toContainText("No public repositories");
  await expect(page.locator(".project-card")).toHaveCount(0);
  await expect(page.locator("#project-retry")).toBeHidden();
  await expect(page.locator("#project-list")).toHaveAttribute("aria-busy", "false");
});

test("HTTP rate limiting is recoverable through retry", async ({ page }) => {
  let attempts = 0;
  await page.route(API, (route) => {
    attempts += 1;
    return attempts === 1 ? route.fulfill({ status: 403, json: { message: "Synthetic quota exceeded" } }) : route.fulfill({ json: repositories });
  });
  await page.goto("/");
  await expect(page.locator("#projects-status")).toContainText("could not be loaded");
  await page.locator("#project-retry").click();
  await expect(page.locator(".project-card")).toHaveCount(3);
  await expect(page.locator("#project-retry")).toBeHidden();
  expect(attempts).toBe(2);
});

test("network failures and unexpected response shapes are honest error states", async ({ page }) => {
  await page.route(API, (route) => route.abort("failed"));
  await page.goto("/");
  await expect(page.locator("#project-retry")).toBeVisible();
  await page.route(API, (route) => route.fulfill({ json: { unexpected: true } }));
  await page.locator("#project-retry").click();
  await expect(page.locator("#projects-status")).toContainText("could not be loaded");
});

test("API text stays text and invalid destinations are excluded", async ({ page }) => {
  const text = '<em data-synthetic="true">Literal repository title</em>';
  await page.route(API, (route) => route.fulfill({ json: [
    { ...repositories[0], name: text, description: text },
    { ...repositories[1], html_url: "javascript:void(0)" },
    { ...repositories[2], html_url: "https://example.invalid/not-github" },
  ] }));
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(1);
  await expect(page.locator(".project-name")).toHaveText(text);
  await expect(page.locator("[data-synthetic]")).toHaveCount(0);
  await expect(page.locator(".project-link")).toHaveAttribute("href", /^https:\/\/github\.com\//);
});

test("request timeout exposes retry instead of an endless spinner", async ({ page }) => {
  await page.route(API, async () => {});
  await page.goto("/");
  await expect(page.locator("#projects-status")).toContainText("too long", { timeout: 12_000 });
  await expect(page.locator("#project-retry")).toBeVisible();
  await expect(page.locator("#project-list")).toHaveAttribute("aria-busy", "false");
});

test("the selected verification backend identifies itself", async ({ request }) => {
  if (process.env.VERIFY_MODE === "vm") {
    const response = await request.get("/__vm-proof.txt");
    expect(response.ok()).toBeTruthy();
    expect(await response.text()).toMatch(/Linux.*x86_64/);
  } else {
    const response = await request.get("/");
    expect(response.ok()).toBeTruthy();
    expect(response.headers().server).toBe("nginx");
  }
});
