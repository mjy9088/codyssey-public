import { expect, test } from "./fixtures.mjs";

test("portfolio matches the pinned renderer baseline", async ({ page }, info) => {
  const response = await page.goto("/");
  expect(response.status()).toBe(200);
  await expect(page.locator(".project-card")).toHaveCount(3);
  await page.evaluate(() => document.fonts.ready);
  await expect(page).toHaveScreenshot(`${info.project.name}.png`, {
    fullPage: true,
    animations: "disabled",
    caret: "hide",
    scale: "css",
    threshold: 0,
    maxDiffPixels: 0,
  });
});
