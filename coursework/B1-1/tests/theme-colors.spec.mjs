import { expect, test } from "./fixtures.mjs";

test("browser theme metadata follows the resolved CSS palette on every toggle", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.locator("html")).toHaveCSS("transition-duration", "0s");
  for (let step = 0; step < 3; step += 1) {
    const paper = await page
      .locator("html")
      .evaluate((element) => getComputedStyle(element).backgroundColor);
    const colors = await page
      .locator('meta[name="theme-color"]')
      .evaluateAll((elements) => elements.map((element) => element.getAttribute("content")));
    expect(colors).toEqual([paper, paper]);
    await page.locator("#theme-toggle").click();
  }
});
