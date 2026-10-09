import type { Page } from "@playwright/test";

export const signIn = async (page: Page): Promise<void> => {
  await page.goto("/login");
  await page.getByLabel("Username").fill("reader");
  await page.getByLabel("Password").fill("correct-horse-battery-staple");
  await page.getByRole("button", { name: "Sign in" }).click();
};
