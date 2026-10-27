import { expect, test } from "./fixtures.mjs";

test("pure email rules preserve the native email input contract", async ({ page }) => {
  await page.goto("/");
  const input = page.locator("#field-email");
  for (const value of [
    "a@b",
    "person+tag@example.invalid",
    "person@sub.example.invalid",
    "not-an-email",
    "two@@example.invalid",
    "person@-example.invalid",
    "person@example..invalid",
    "müller@example.invalid",
  ]) {
    await input.fill(value);
    const invalid = await input.evaluate((element) => !element.validity.valid);
    await input.blur();
    await expect(input).toHaveAttribute("aria-invalid", String(invalid));
    if (invalid) await expect(page.locator("#error-email")).not.toBeEmpty();
    else await expect(page.locator("#error-email")).toBeEmpty();
  }
});
