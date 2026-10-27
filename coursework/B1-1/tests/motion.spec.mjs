import { expect, test } from "./fixtures.mjs";

test("revealed project cards retain their own hover and keyboard transitions", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/");
  const card = page.locator(".project-card").first();
  await card.scrollIntoViewIfNeeded();
  await expect(card).toHaveCSS("opacity", "1");
  await expect(card).not.toHaveCSS("box-shadow", "none");
  await page.mouse.move(0, 0);

  await card.hover();
  await expect(card).toHaveCSS("transform", "matrix(1, 0, 0, 1, 0, -4)");
  const transition = await card.evaluate((element) => getComputedStyle(element).transitionProperty);
  expect(transition.split(",").map((property) => property.trim())).toContain("border-color");

  await page.mouse.move(0, 0);
  await card.locator("a").focus();
  await expect(card).toHaveCSS("transform", "matrix(1, 0, 0, 1, 0, -4)");
});

test("reduced motion keeps revealed project cards stationary during interaction", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  const card = page.locator(".project-card").first();
  await card.scrollIntoViewIfNeeded();
  await card.hover();
  const movement = await card.evaluate((element) => {
    const style = getComputedStyle(element);
    return { transform: style.transform, translate: style.translate };
  });
  expect(["none", "matrix(1, 0, 0, 1, 0, 0)"]).toContain(movement.transform);
  expect(["none", "0px", "0px 0px"]).toContain(movement.translate);
  await expect(card).toHaveCSS("opacity", "1");
});
