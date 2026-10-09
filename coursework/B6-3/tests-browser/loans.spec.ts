import { expect, test } from "@playwright/test";
import { signIn } from "./session.js";

test("borrows, rejects a duplicate loan, and returns a title", async ({
  page,
}) => {
  // Given: an authenticated member creates an available book.
  await signIn(page);
  await page.goto("/books/new");
  await page.getByLabel("Title").fill("Browser Loan Fixture");
  await page.getByLabel("Author").fill("Test Reader");
  await page.getByLabel("Publication year").fill("2025");
  await page.getByLabel("Total copies").fill("1");
  await page.getByRole("button", { name: "Add to catalog" }).click();
  const borrowAction = await page
    .locator('form[action$="/borrow"]')
    .getAttribute("action");
  expect(borrowAction).not.toBeNull();

  // When: the member borrows the only copy.
  await page.getByRole("button", { name: "Borrow this book" }).click();

  // Then: the active loan appears in the borrowed view.
  await expect(page).toHaveURL(/\/loans\?loan_status=borrowed$/);
  const loan = page
    .getByRole("article")
    .filter({ hasText: "Browser Loan Fixture" });
  await expect(loan.getByText("borrowed", { exact: true })).toBeVisible();

  // When: the member attempts the same borrow action again.
  const csrfToken = await loan.locator('input[name="csrf_token"]').inputValue();
  const duplicateResponse = await page.request.post(borrowAction ?? "", {
    form: { csrf_token: csrfToken },
  });

  // Then: the domain conflict is reported and the original loan remains actionable.
  expect(duplicateResponse.status()).toBe(409);
  await expect(loan.getByRole("button", { name: "Return book" })).toBeVisible();

  // When: the member returns the active loan.
  await page.goto("/loans?loan_status=borrowed");
  await loan.getByRole("button", { name: "Return book" }).click();

  // Then: the member can filter to the completed loan with no return action.
  await expect(page).toHaveURL(/\/loans$/);
  await page.getByRole("link", { name: "Returned" }).click();
  await expect(page).toHaveURL(/\/loans\?loan_status=returned$/);
  const returnedLoan = page
    .getByRole("article")
    .filter({ hasText: "Browser Loan Fixture" });
  await expect(
    returnedLoan.getByText("returned", { exact: true }),
  ).toBeVisible();
  await expect(
    returnedLoan.getByRole("button", { name: "Return book" }),
  ).toHaveCount(0);
});
