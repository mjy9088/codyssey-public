import { API, expect, repositories, test } from "./fixtures.mjs";

test("system theme changes stay live until an explicit choice, even without storage", async ({
  page,
}) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, "localStorage", {
      get: () => {
        throw new DOMException("Blocked", "SecurityError");
      },
    });
  });
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto("/");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await expect(page.locator("#theme-toggle")).toHaveAttribute("aria-pressed", "true");
  await page.locator("#theme-toggle").click();
  await page.emulateMedia({ colorScheme: "light" });
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
});

test("filtering disconnects observers from removed cards", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.addInitScript(() => {
    window.observedRevealTargets = new Set();
    const NativeObserver = window.IntersectionObserver;
    window.IntersectionObserver = class extends NativeObserver {
      targets = new Set();
      observe(target) {
        this.targets.add(target);
        window.observedRevealTargets.add(target);
        super.observe(target);
      }
      unobserve(target) {
        this.targets.delete(target);
        window.observedRevealTargets.delete(target);
        super.unobserve(target);
      }
      disconnect() {
        this.targets.forEach((target) => {
          window.observedRevealTargets.delete(target);
        });
        this.targets.clear();
        super.disconnect();
      }
    };
  });
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(3);
  const filter = page.locator("#project-filter");
  for (const language of ["JavaScript", "all", "HTML", "all"]) {
    await filter.selectOption(language);
    expect(
      await page.evaluate(
        () => [...window.observedRevealTargets].filter((target) => !target.isConnected).length,
      ),
    ).toBe(0);
  }
  await page.locator("#project-list").scrollIntoViewIfNeeded();
  await expect(page.locator(".project-card.is-visible")).toHaveCount(3);
});

test("invalid records are reported and cannot masquerade as an empty account", async ({ page }) => {
  const invalid = [
    null,
    { ...repositories[0], name: "   " },
    { ...repositories[0], html_url: "https://user:password@github.com/mjy9088/example" },
    { ...repositories[0], html_url: "https://github.com:8443/mjy9088/example" },
    { ...repositories[0], updated_at: "not-a-date" },
    { ...repositories[0], fork: "false" },
  ];
  await page.route(API, (route) => route.fulfill({ json: [...invalid, repositories[0]] }));
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(1);
  await expect(page.locator("#projects-status")).toContainText("6 invalid records skipped");
  await page.route(API, (route) => route.fulfill({ json: invalid }));
  await page.reload();
  await expect(page.locator("#projects-status")).toContainText("could not be loaded");
  await expect(page.locator("#project-retry")).toBeVisible();
  await expect(page.locator("#project-filter")).toBeDisabled();
  await page.route(API, (route) => route.fulfill({ json: repositories }));
  await page.locator("#project-retry").click();
  await expect(page.locator(".project-card")).toHaveCount(3);
  await expect(page.locator("#projects-status")).not.toContainText("skipped");
});

test("input and render caps apply independently of fork exclusion", async ({ page }) => {
  const candidates = Array.from({ length: 20 }, (_, index) => ({
    ...repositories[0],
    name: `candidate-${index}`,
  }));
  await page.route(API, (route) => route.fulfill({ json: [repositories[3], ...candidates] }));
  await page.goto("/");
  await expect(page.locator(".project-card")).toHaveCount(12);
  await expect(page.locator(".project-name").first()).toHaveText("candidate-0");
  await expect(page.locator(".project-name").last()).toHaveText("candidate-11");
  await page.route(API, (route) =>
    route.fulfill({
      json: [...Array.from({ length: 100 }, () => repositories[3]), repositories[0]],
    }),
  );
  await page.reload();
  await expect(page.locator("#projects-status")).toContainText("No public repositories");
  await expect(page.locator(".project-card")).toHaveCount(0);
});

test("validated fields remain accurate while editing and submission focuses the first error", async ({
  page,
}) => {
  await page.goto("/");
  const name = page.locator("#field-name");
  await name.fill("Reviewer");
  await page.locator("#field-email").focus();
  await expect(name).toHaveAttribute("aria-invalid", "false");
  await name.fill("   ");
  await expect(name).toHaveAttribute("aria-invalid", "true");
  await expect(page.locator("#error-name")).not.toBeEmpty();
  await name.fill("Reviewer");
  await expect(name).toHaveAttribute("aria-invalid", "false");
  await expect(page.locator("#error-name")).toBeEmpty();
  await page.locator('#contact-form button[type="submit"]').click();
  await expect(page.locator("#field-email")).toBeFocused();
});

test("Skills names concrete technologies without inventing proficiency", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#skills .tag-list li")).toContainText([
    "HTML",
    "CSS",
    "JavaScript",
    "Git",
    "Docker",
    "Playwright",
  ]);
});

test.describe("repository date semantics", () => {
  test.use({ timezoneId: "America/Los_Angeles" });
  test("UTC month does not shift with the visitor timezone", async ({ page }) => {
    await page.route(API, (route) =>
      route.fulfill({ json: [{ ...repositories[0], updated_at: "2026-02-01T00:00:00Z" }] }),
    );
    await page.goto("/");
    await expect(page.locator(".project-date")).toHaveText("Feb 2026");
  });
});
