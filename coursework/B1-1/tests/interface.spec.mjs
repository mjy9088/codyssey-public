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

test("system palette is correct before deferred JavaScript finishes loading", async ({ page }, info) => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  await page.route("**/js/app.js", async (route) => { await gate; await route.continue(); });
  try {
    await page.goto("/", { waitUntil: "commit" });
    await page.locator("body").waitFor({ state: "attached" });
    const color = info.project.name === "dark" ? "rgb(21, 24, 22)" : "rgb(244, 241, 232)";
    await expect.poll(() => page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe(color);
    const dark = info.project.name === "dark";
    await expect(page.locator(".portrait img")).toHaveCSS("filter", dark ? "invert(1) hue-rotate(180deg)" : "none");
    await expect(page.locator(dark ? ".theme-icon-sun" : ".theme-icon-moon")).toBeVisible();
    await expect(page.locator(dark ? ".theme-icon-moon" : ".theme-icon-sun")).toBeHidden();
    await expect(page.locator(`#theme-toggle`)).toHaveAttribute("aria-label", "Toggle color theme");
    await expect(page.locator(`meta[name="theme-color"][media="(prefers-color-scheme: ${dark ? "dark" : "light"})"]`)).toHaveAttribute("content", dark ? "#151816" : "#f4f1e8");
  } finally {
    release();
  }
  await expect(page.locator("html")).toHaveAttribute("data-theme", info.project.name === "dark" ? "dark" : "light");
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
    await expect(toggle.locator(".menu-icon-close")).toBeVisible();
    await expect(toggle.locator(".menu-icon-open")).not.toBeVisible();
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
  await expect(page.locator("#form-status")).toHaveAttribute("data-state", "error");
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
  await expect(page.locator("#form-status")).toHaveAttribute("data-state", "success");
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

test("input and select boundaries have at least three-to-one contrast", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(3);
  const pairs = await page.evaluate(() => ["#field-name", "#field-email", "#field-message", "#project-filter"].flatMap((selector) => {
    const style = getComputedStyle(document.querySelector(selector));
    const surrounding = getComputedStyle(document.querySelector(selector === "#project-filter" ? "body" : "#contact"));
    return [[style.borderTopColor, style.backgroundColor], [style.borderTopColor, surrounding.backgroundColor]];
  }));
  const luminance = (color) => {
    const channels = color.match(/[\d.]+/g).slice(0, 3).map(Number).map((value) => {
      const normalized = value / 255;
      return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
    });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  for (const [border, background] of pairs) {
    const [a, b] = [luminance(border), luminance(background)].sort((left, right) => right - left);
    expect((a + 0.05) / (b + 0.05)).toBeGreaterThanOrEqual(3);
  }
});
