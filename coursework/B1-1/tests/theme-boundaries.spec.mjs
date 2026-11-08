import { expect, test } from "./fixtures.mjs";

test("invalid stored preferences follow the system until a valid explicit choice is saved", async ({
  page,
}) => {
  await page.addInitScript(() => localStorage.setItem("portfolio-theme", "invalid"));
  await page.emulateMedia({ colorScheme: "dark" });
  await page.goto("/");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.emulateMedia({ colorScheme: "light" });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  await page.locator("#theme-toggle").click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  expect(await page.evaluate(() => localStorage.getItem("portfolio-theme"))).toBe("dark");
});

test("a storage quota failure cannot give later system changes priority over a clicked choice", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.addInitScript(() => {
    Storage.prototype.setItem = () => {
      throw new DOMException("Full", "QuotaExceededError");
    };
  });
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto("/");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.locator("#theme-toggle").click();
  await page.emulateMedia({ colorScheme: "light" });
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  expect(errors).toEqual([]);
});

test("theme disposal releases native preference observation and the click handler", async ({
  page,
}) => {
  await page.route("**/js/app.js", (route) =>
    route.fulfill({ contentType: "text/javascript", body: "" }),
  );
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto("/");
  await page.evaluate(async () => {
    const { createThemePreferences } = await import("/js/data/theme-preferences.js");
    const { initTheme } = await import("/js/ui/theme.js");
    window.stopTheme = initTheme(createThemePreferences());
  });
  await expect(page.locator("#theme-toggle")).toBeVisible();
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.evaluate(() => window.stopTheme());
  await expect(page.locator("#theme-toggle")).toBeHidden();
  await page.emulateMedia({ colorScheme: "light" });
  await page.evaluate(() => document.querySelector("#theme-toggle").click());
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  expect(await page.evaluate(() => localStorage.getItem("portfolio-theme"))).toBeNull();
});
