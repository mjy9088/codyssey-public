import { mkdir } from "node:fs/promises";
import AxeBuilder from "@axe-core/playwright";
import { test, expect } from "./fixtures.mjs";

test("semantic page, local assets, responsive layout and screenshot", async ({ page }, info) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const response = await page.goto("/");
  expect(response.status()).toBe(200);
  await expect(page.locator(".project-card")).toHaveCount(3);
  await expect(page.locator("h1")).toHaveCount(1);
  for (const id of ["home", "about", "skills", "projects", "contact"]) {
    await expect(page.locator(`section#${id}`)).toBeVisible();
  }
  const layout = await page.evaluate(() => ({
    overflow: document.documentElement.scrollWidth > innerWidth,
    images: [...document.images].every((image) => image.complete && image.naturalWidth > 0 && image.alt.trim()),
    inlineStyles: document.querySelectorAll("[style]").length,
    inlineEvents: [...document.querySelectorAll("*")].some((el) => [...el.attributes].some((attr) => /^on/i.test(attr.name))),
  }));
  expect(layout).toEqual({ overflow: false, images: true, inlineStyles: 0, inlineEvents: false });
  expect(errors).toEqual([]);
  await page.evaluate(() => document.fonts.ready);
  if (info.project.name !== "tablet") {
    await expect(page).toHaveScreenshot(`${info.project.name}.png`, {
      fullPage: true, animations: "disabled", caret: "hide", scale: "css",
      threshold: 0, maxDiffPixels: 0,
    });
  }
  await mkdir("artifacts/screenshots", { recursive: true });
  await page.screenshot({ path: `artifacts/screenshots/${info.project.name}.png`, fullPage: true, animations: "disabled", caret: "hide", scale: "css" });
});

test("theme responds to preference and persists an explicit choice", async ({ page }, info) => {
  await page.goto("/");
  const initial = info.project.name === "dark" ? "dark" : "light";
  const next = initial === "dark" ? "light" : "dark";
  await expect(page.locator("html")).toHaveAttribute("data-theme", initial);
  await page.locator("#theme-toggle").click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", next);
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", next);
  await expect(page.locator("#theme-toggle")).toHaveAttribute("aria-pressed", String(next === "dark"));
});

test("denied storage does not break theme or application startup", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, "localStorage", { get: () => { throw new DOMException("Blocked", "SecurityError"); } });
  });
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(3);
  const before = await page.locator("html").getAttribute("data-theme");
  await page.locator("#theme-toggle").click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", before === "dark" ? "light" : "dark");
});

test("navigation is keyboard operable and closes on Escape and selection", async ({ page }) => {
  await page.goto("/");
  if (page.viewportSize().width < 768) {
    const toggle = page.locator("#menu-toggle");
    await expect(page.locator("#primary-nav")).not.toBeVisible();
    await toggle.focus();
    await page.keyboard.press("Enter");
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    await expect(page.locator("#primary-nav")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await expect(toggle).toBeFocused();
    await toggle.click();
    await page.locator('#primary-nav a[href="#projects"]').click();
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
  } else {
    await expect(page.locator("#menu-toggle")).not.toBeVisible();
    await page.locator('#primary-nav a[href="#projects"]').click();
  }
  await expect(page).toHaveURL(/#projects$/);
  await expect(page.locator("#projects")).toBeFocused();
});

test("scroll controls and reduced motion reflect viewport state", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#back-to-top")).toHaveAttribute("tabindex", "-1");
  await page.evaluate(() => scrollTo(0, 500));
  await expect(page.locator("#site-header")).toHaveClass(/is-scrolled/);
  await expect(page.locator("#back-to-top")).toHaveClass(/is-visible/);
  await expect(page.locator("#back-to-top")).toHaveAttribute("tabindex", "0");
  await page.locator("#back-to-top").click();
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(0);
  await expect(page.locator("#main-content")).toBeFocused();
  await expect(page.locator("#back-to-top")).toHaveAttribute("tabindex", "-1");
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior)).toBe("auto");
});

test("form rejects missing, blank and malformed values without sending data", async ({ page }) => {
  await page.goto("/");
  await page.locator('#contact-form button[type="submit"]').click();
  for (const name of ["name", "email", "message"]) {
    await expect(page.locator(`#field-${name}`)).toHaveAttribute("aria-invalid", "true");
    await expect(page.locator(`#error-${name}`)).not.toBeEmpty();
  }
  await page.locator("#field-name").fill("   ");
  await expect(page.locator("#field-name")).toHaveAttribute("aria-invalid", "true");
  await page.locator("#field-name").fill("Reviewer");
  await page.locator("#field-email").fill("not-an-email");
  await page.locator("#field-message").fill("A local review note.");
  await page.locator('#contact-form button[type="submit"]').click();
  await expect(page.locator("#field-email")).toHaveAttribute("aria-invalid", "true");
  await page.locator("#field-email").fill("reviewer@example.invalid");
  const requests = [];
  page.on("request", (request) => requests.push(request.url()));
  await page.locator('#contact-form button[type="submit"]').click();
  await expect(page.locator("#form-status")).toContainText("nothing was submitted");
  expect(requests).toEqual([]);
  expect(page.url()).not.toContain("reviewer");
});

test("automated accessibility checks pass for populated and invalid form states", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(3);
  const scan = () => new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"]).analyze();
  expect((await scan()).violations).toEqual([]);
  await page.locator('#contact-form button[type="submit"]').click();
  expect((await scan()).violations).toEqual([]);
});
