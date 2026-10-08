import { test as base, expect } from "@playwright/test";

export const API = "https://api.github.com/users/mjy9088/repos*";
export const repositories = [
  { name: "field-notes", description: "A small notebook for useful observations.", language: "JavaScript", html_url: "https://github.com/mjy9088/field-notes", updated_at: "2026-01-12T09:00:00Z", fork: false },
  { name: "paper-trail", description: "Clear documentation for repeatable work.", language: "HTML", html_url: "https://github.com/mjy9088/paper-trail", updated_at: "2026-01-10T09:00:00Z", fork: false },
  { name: "small-tools", description: null, language: null, html_url: "https://github.com/mjy9088/small-tools", updated_at: "2026-01-08T09:00:00Z", fork: false },
  { name: "upstream-example", description: "A fork excluded from selected work.", language: "JavaScript", html_url: "https://github.com/mjy9088/upstream-example", updated_at: "2026-01-06T09:00:00Z", fork: true },
];

export const test = base.extend({
  page: async ({ page, baseURL }, use) => {
    const origin = new URL(baseURL).origin;
    await page.route("**/*", async (route) => {
      const url = new URL(route.request().url());
      if (url.origin === origin) return route.continue();
      if (url.origin === "https://api.github.com") return route.fulfill({ json: repositories });
      return route.abort("blockedbyclient");
    });
    await use(page);
  },
});

export { expect };
