import { expect, test } from "@playwright/test";
import { signIn } from "./session.js";

test("validates, creates, edits, searches, and deletes a catalog record", async ({
  page,
}) => {
  // Given: an authenticated member opens the add-book form.
  await signIn(page);
  await page.goto("/books/new");

  // When: the member submits a title that becomes empty after normalization.
  await page.getByLabel("Title").fill("   ");
  await page.getByLabel("Author").fill("Test Reader");
  await page.getByLabel("Publication year").fill("2024");
  await page.getByLabel("Total copies").fill("2");
  await page.getByRole("button", { name: "Add to catalog" }).click();

  // Then: the form reports an inline validation error.
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page.getByLabel("Author")).toHaveValue("Test Reader");
  await expect(page.getByLabel("Publication year")).toHaveValue("2024");
  await expect(page.getByLabel("Total copies")).toHaveValue("2");

  // When: the member corrects the title and saves the record.
  await page.getByLabel("Title").fill("Browser Test Almanac");
  await page.getByRole("button", { name: "Add to catalog" }).click();

  // Then: the new record detail is visible.
  await expect(page).toHaveURL(/\/books\/\d+$/);
  await expect(
    page.getByRole("heading", { name: "Browser Test Almanac" }),
  ).toBeVisible();

  // When: the member submits invalid edits with otherwise changed values.
  await page.getByRole("link", { name: "Edit record" }).click();
  await page.getByLabel("Title").fill("   ");
  await page.getByLabel("Author").fill("Updated Test Reader");
  await page.getByLabel("Publication year").fill("2023");
  await page.getByRole("button", { name: "Save changes" }).click();

  // Then: the edit form reports the error and retains every submitted value.
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page.getByLabel("Author")).toHaveValue("Updated Test Reader");
  await expect(page.getByLabel("Publication year")).toHaveValue("2023");
  await expect(page.getByLabel("Total copies")).toHaveValue("2");

  // When: the member corrects the edited title and searches for it.
  await page.getByLabel("Title").fill("Browser Test Field Guide");
  await page.getByRole("button", { name: "Save changes" }).click();
  await page.goto("/books");
  await page.getByLabel("Title or author").fill("Browser Test Field Guide");
  await page.getByRole("button", { name: "Search" }).click();

  // Then: only the renamed record is surfaced and can be deleted explicitly.
  await expect(
    page.getByRole("heading", { name: "Browser Test Field Guide" }),
  ).toBeVisible();
  await page.getByRole("link", { name: "Browser Test Field Guide" }).click();
  await page.getByText("Remove this catalog record").click();
  await page.getByRole("button", { name: "Delete permanently" }).click();
  await expect(page).toHaveURL(/\/books$/);
});

test("mobile search and empty results remain contained", async ({ page }) => {
  const query = "unbroken-search-term-".repeat(12);

  // Given: an authenticated member opens the catalog on a phone-sized viewport.
  await signIn(page);
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/books");

  // When: the member searches with a long query that has no matches.
  await page.getByLabel("Title or author").fill(query);
  await page.getByRole("button", { name: "Search" }).click();

  // Then: the empty state and retained search fit without horizontal overflow.
  await expect(page.getByRole("heading", { name: "Try another shelf." })).toBeVisible();
  await expect(page.getByLabel("Title or author")).toHaveValue(query);
  const viewportFits = await page.evaluate(
    () => document.documentElement.scrollWidth <= window.innerWidth,
  );
  expect(viewportFits).toBe(true);
});
