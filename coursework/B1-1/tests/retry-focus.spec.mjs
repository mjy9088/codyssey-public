import { API, expect, repositories, test } from "./fixtures.mjs";

for (const scenario of [
  { name: "success", response: { json: repositories }, target: "#project-filter" },
  { name: "empty", response: { json: [] }, target: "#projects-status" },
  { name: "repeated failure", response: { status: 403, json: {} }, target: "#project-retry" },
]) {
  test(`keyboard retry retains a useful focus destination after ${scenario.name}`, async ({
    page,
  }) => {
    let release;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    let attempts = 0;
    await page.route(API, async (route) => {
      if (attempts++ === 0) return route.fulfill({ status: 403, json: {} });
      await gate;
      return route.fulfill(scenario.response);
    });
    await page.goto("/");
    await expect(page.locator("#project-retry")).toBeVisible();
    await page.locator("#project-retry").focus();
    await page.keyboard.press("Enter");
    try {
      await expect(page.locator("#projects-status")).toBeFocused();
      await expect(page.locator("#project-list")).toHaveAttribute("aria-busy", "true");
    } finally {
      release();
    }
    await expect(page.locator(scenario.target)).toBeFocused();
    await expect(page.locator("#project-list")).toHaveAttribute("aria-busy", "false");
  });
}

test("a retry response does not steal focus after the visitor moves elsewhere", async ({
  page,
}) => {
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  let attempts = 0;
  await page.route(API, async (route) => {
    if (attempts++ === 0) return route.fulfill({ status: 403, json: {} });
    await gate;
    return route.fulfill({ json: repositories });
  });
  await page.goto("/");
  await expect(page.locator("#project-retry")).toBeVisible();
  await page.locator("#project-retry").click();
  try {
    await page.locator("#field-name").focus();
  } finally {
    release();
  }
  await expect(page.locator(".project-card")).toHaveCount(3);
  await expect(page.locator("#field-name")).toBeFocused();
});
