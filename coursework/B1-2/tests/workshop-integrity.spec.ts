import { type APIRequestContext, expect, test } from "@playwright/test"
import { documentsUrl, resetDocumentsUrl } from "./emulator-endpoints"

const documents = `${documentsUrl}/workshops`

const storeFixture = async (request: APIRequestContext, id: string, title: string) => {
  const response = await request.patch(`${documents}/${encodeURIComponent(id)}`, {
    headers: { Authorization: "Bearer owner" },
    data: {
      fields: {
        id: { stringValue: "other-workshop" },
        title: { stringValue: title },
        summary: { stringValue: "A synthetic workshop for identity boundary verification." },
        facilitator: { stringValue: "Test Facilitator" },
        location: { stringValue: "Local bench" },
        startsAt: { stringValue: "2026-12-10T14:00" },
        capacity: { integerValue: "8" },
        status: { stringValue: "open" },
      },
    },
  })
  expect(response.ok()).toBeTruthy()
}

test.beforeEach(async ({ request }) => {
  const reset = await request.delete(resetDocumentsUrl)
  expect(reset.ok()).toBeTruthy()
  await storeFixture(request, "actual-workshop", "Original workshop")
  await storeFixture(request, "other-workshop", "Other workshop")
})

test("list links use Firestore document identity, not an id field in stored data", async ({
  page,
}) => {
  await page.goto("/workshops")
  await expect(page.getByRole("link", { name: "Original workshop", exact: true })).toHaveAttribute(
    "href",
    "/workshops/actual-workshop",
  )
})

test("detail edits and deletes only the requested document despite a conflicting stored id", async ({
  page,
  request,
}) => {
  await page.goto("/workshops/actual-workshop")
  await expect(page.getByRole("heading", { name: "Original workshop", exact: true })).toBeVisible()
  await expect(page.getByRole("link", { name: "Edit", exact: true })).toHaveAttribute(
    "href",
    "/workshops/actual-workshop/edit",
  )
  await page.getByRole("link", { name: "Edit", exact: true }).click()
  await page.getByLabel("Workshop title").fill("Updated original workshop")
  await page.getByRole("button", { name: "Save changes" }).click()
  await expect(page).toHaveURL(/\/workshops\/actual-workshop$/)
  await page.reload()
  await expect(
    page.getByRole("heading", { name: "Updated original workshop", exact: true }),
  ).toBeVisible()
  await page.getByRole("button", { name: "Delete", exact: true }).click()
  await page.getByRole("button", { name: "Delete permanently" }).click()
  await expect(page.getByRole("status").filter({ hasText: "Workshop deleted." })).toBeVisible()
  await expect(page.getByRole("link", { name: "Other workshop", exact: true })).toBeVisible()
  const removed = await request.get(`${documents}/actual-workshop`, {
    headers: { Authorization: "Bearer owner" },
  })
  expect(removed.status()).toBe(404)
  await page.goto("/workshops/other-workshop")
  await expect(page.getByRole("heading", { name: "Other workshop", exact: true })).toBeVisible()
})

test("preserves document identity through URL-reserved characters in links and edit navigation", async ({
  page,
  request,
}) => {
  const id = "workshop?query#fragment%literal"
  const path = `/workshops/${encodeURIComponent(id)}`
  await storeFixture(request, id, "Reserved identity workshop")
  await page.goto("/workshops")
  const link = page.getByRole("link", { name: "Reserved identity workshop", exact: true })
  await expect(link).toHaveAttribute("href", path)
  await link.click()
  await expect(
    page.getByRole("heading", { level: 1, name: "Reserved identity workshop", exact: true }),
  ).toBeVisible()
  await page.getByRole("link", { name: "Edit", exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`${encodeURIComponent(id)}/edit$`))
  await page.getByLabel("Workshop title").fill("Updated reserved identity workshop")
  await page.getByRole("button", { name: "Save changes" }).click()
  await expect(
    page.getByRole("heading", {
      level: 1,
      name: "Updated reserved identity workshop",
      exact: true,
    }),
  ).toBeVisible()
  await expect(page).toHaveURL(`${new URL(page.url()).origin}${path}`)
  await page.reload()
  await expect(
    page.getByRole("heading", {
      level: 1,
      name: "Updated reserved identity workshop",
      exact: true,
    }),
  ).toBeVisible()
})
