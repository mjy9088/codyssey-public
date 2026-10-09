import { expect, test } from "@playwright/test";

test("redirects protected visitors and starts a member session", async ({
  page,
}) => {
  // Given: a signed-out browser requests protected showcase and catalog routes.
  await page.goto("/showcase");
  await expect(page).toHaveURL(/\/login\?next=\/showcase$/);
  await page.goto("/books");

  // When: the visitor submits invalid credentials.
  await expect(page).toHaveURL(/\/login\?next=\/books$/);
  await page.getByLabel("Username").fill("reader");
  await page.getByLabel("Password").fill("incorrect-password");
  await page.getByRole("button", { name: "Sign in" }).click();

  // Then: authentication fails without exposing the protected page.
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page).toHaveURL(/\/login$/);

  // When: the visitor submits the seeded member credentials.
  await page.getByLabel("Username").fill("reader");
  await page.getByLabel("Password").fill("correct-horse-battery-staple");
  await page.getByRole("button", { name: "Sign in" }).click();

  // Then: the authenticated home opens with the member shell.
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByText("Demo Reader")).toBeVisible();
  const catalogNavigation = page.getByRole("link", {
    name: "Catalog",
    exact: true,
  });
  await catalogNavigation.click();
  await expect(catalogNavigation).toHaveAttribute("aria-current", "page");

  // When: the member requests a catalog record that does not exist.
  await page.goto("/books/999999");

  // Then: a recovery-oriented missing-record page is rendered.
  await expect(page).toHaveURL(/\/books\/999999$/);
  await expect(
    page.getByRole("heading", { name: "This book is not on the shelf." }),
  ).toBeVisible();
  await expect(page.getByText("Demo Reader")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign out" })).toBeVisible();

  // When: the member opens the authenticated component reference.
  await page.goto("/showcase");

  // Then: reusable controls, records, and states render in the member shell.
  await expect(
    page.getByRole("heading", { name: "Folio interface showcase." }),
  ).toBeVisible();
  await expect(page.getByText("Demo Reader")).toBeVisible();

  // When: the member signs out through the rendered session control.
  await page.getByRole("button", { name: "Sign out" }).click();

  // Then: the session is invalidated and protected routes require authentication again.
  await expect(page).toHaveURL(/\/login$/);
  await page.goto("/books");
  await expect(page).toHaveURL(/\/login\?next=\/books$/);
});
