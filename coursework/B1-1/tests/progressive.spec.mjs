import { expect, test } from "./fixtures.mjs";

test("an initialization fault does not globally conceal static content", async ({ page }) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error));
  await page.addInitScript(() => {
    const observer = new MutationObserver(() => {
      for (const element of document.querySelectorAll('meta[name="theme-color"]')) element.remove();
    });
    observer.observe(document, { childList: true, subtree: true });
    document.addEventListener("DOMContentLoaded", () => observer.disconnect(), { once: true });
  });
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/");
  await expect.poll(() => errors.length).toBe(1);
  await expect(page.locator("html")).toHaveClass(/js/);
  await expect(page.locator(".hero-copy")).toHaveCSS("opacity", "1");
  await expect(page.locator("#about .section-heading")).toHaveCSS("opacity", "1");
  await expect(page.locator(".is-reveal-pending")).toHaveCount(0);
});

test("content and safe contact behavior survive disabled JavaScript", async ({
  browser,
  baseURL,
}, info) => {
  const context = await browser.newContext({
    javaScriptEnabled: false,
    viewport: info.project.use.viewport,
  });
  const page = await context.newPage();
  await page.route("**/*", (route) =>
    new URL(route.request().url()).origin === new URL(baseURL).origin
      ? route.continue()
      : route.abort(),
  );
  try {
    await page.goto(baseURL);
    await expect(page.locator("h1")).toBeVisible();
    await expect(page.locator("#about h2")).toBeVisible();
    await expect(page.locator("#primary-nav")).toBeVisible();
    await expect(page.locator('#contact-form button[type="submit"]')).toBeDisabled();
    await expect(page.locator("#projects noscript p")).toBeVisible();
    await expect(page.locator("#projects noscript p")).toContainText("JavaScript is off");
  } finally {
    await context.close();
  }
});

test("normal-motion observer reveals content and anchor targets remain usable", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/");
  const heading = page.locator("#skills .section-heading");
  await heading.scrollIntoViewIfNeeded();
  await expect(heading).toHaveClass(/is-visible/);
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior)).toBe(
    "smooth",
  );
});

test("long public metadata wraps without horizontal overflow", async ({ page }) => {
  await page.route("https://api.github.com/**", (route) =>
    route.fulfill({
      json: [
        {
          name: "long-project-".repeat(40),
          description: "A".repeat(1000),
          language: "LongLanguage".repeat(20),
          html_url: "https://github.com/mjy9088/example",
          updated_at: "2026-01-12T00:00:00Z",
          fork: false,
        },
      ],
    }),
  );
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
