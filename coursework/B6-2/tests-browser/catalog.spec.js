import { expect, test } from "@playwright/test"

test("catalog supports a complete book lifecycle", async ({ page }) => {
  await test.step("Given an empty catalog", async () => {
    await page.goto("/books")
    await expect(page.locator(".catalog")).toHaveCount(0)
  })

  await test.step("When a reader adds and edits a book", async () => {
    await page.getByRole("link", { name: "Add a book" }).first().click()
    await page.getByLabel("Title").fill("The Left Hand of Darkness")
    await page.getByLabel("Author").fill("Ursula K. Le Guin")
    await page.getByLabel("Publication year").fill("1969")
    await page.getByRole("button", { name: "Add to catalog" }).click()
    await expect(page).toHaveURL(/\/books\/\d+\?notice=created$/)

    await page.getByRole("link", { name: "Edit record" }).click()
    await page.getByLabel("Title").fill("The Dispossessed")
    await page.getByLabel("Publication year").fill("1974")
    await page.getByRole("button", { name: "Save changes" }).click()
  })

  await test.step("Then the updated record can be searched and removed", async () => {
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("The Dispossessed")
    await page.getByRole("link", { name: "Back to catalog" }).click()
    await page.getByLabel("Search the catalog").fill("Dispossessed")
    await page.getByRole("button", { name: "Search" }).click()
    await expect(page.locator(".book-card")).toHaveCount(1)
    await page.getByRole("link", { name: "The Dispossessed" }).click()
    await page.getByRole("link", { name: "Remove" }).click()
    await page.getByRole("button", { name: "Remove book" }).click()
    await expect(page).toHaveURL(/\/books\?notice=deleted$/)
    await expect(page.locator(".catalog")).toHaveCount(0)
  })
})

test("invalid input is retained and missing records return 404", async ({ page }) => {
  await test.step("Given a new-book form", async () => {
    await page.goto("/books/new")
  })

  await test.step("When invalid values are submitted", async () => {
    await page.getByLabel("Title").fill("A")
    await page.getByLabel("Author").fill("B")
    await page.getByLabel("Publication year").fill("1200")
    await page.locator("form.book-form").evaluate((form) => {
      form.noValidate = true
    })
    await page.getByRole("button", { name: "Add to catalog" }).click()
  })

  await test.step("Then validation and missing-record states are accessible", async () => {
    await expect(page.getByRole("alert")).toBeVisible()
    await expect(page.getByLabel("Publication year")).toHaveValue("1200")
    const response = await page.goto("/books/999999")
    expect(response?.status()).toBe(404)
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible()
  })
})

test("home and showcase remain usable on a narrow viewport", async ({ page }) => {
  await test.step("Given a phone-sized viewport", async () => {
    await page.setViewportSize({ width: 390, height: 844 })
    await page.goto("/")
  })

  await test.step("When the reader navigates the interface reference", async () => {
    await expect(page.getByRole("main")).toBeVisible()
    await page.goto("/showcase")
  })

  await test.step("Then controls fit without horizontal overflow", async () => {
    await expect(page.getByRole("button", { name: "Primary action" })).toBeVisible()
    await expect(page.getByRole("button", { name: "Unavailable action" })).toBeDisabled()
    await expect(page.getByRole("heading", { name: "Your catalog is ready for its first book." })).toBeVisible()
    const viewportFits = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    expect(viewportFits).toBe(true)
  })
})

test("mobile catalog search and empty states do not overflow", async ({ page }) => {
  const longQuery = "unbroken-search-term-".repeat(12)

  await test.step("Given an empty catalog on a phone-sized viewport", async () => {
    await page.setViewportSize({ width: 390, height: 844 })
    await page.goto("/books")
    await expect(page.getByRole("heading", { name: "Your catalog is ready for its first book." })).toBeVisible()
  })

  await test.step("When a reader searches for a long unmatched title", async () => {
    await page.getByLabel("Search the catalog").fill(longQuery)
    await page.getByRole("button", { name: "Search" }).click()
  })

  await test.step("Then the no-match state and controls fit the viewport", async () => {
    await expect(page.getByRole("heading", { name: "No books match your search." })).toBeVisible()
    await expect(page.getByLabel("Search the catalog")).toHaveValue(longQuery)
    await expect(page.getByRole("link", { name: "Clear search" })).toBeVisible()
    const viewportFits = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    expect(viewportFits).toBe(true)
  })
})
