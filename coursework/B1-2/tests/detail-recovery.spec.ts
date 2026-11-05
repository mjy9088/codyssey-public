import { expect, test } from "@playwright/test"
import { documentsUrl } from "./emulator-endpoints"

const fixtureUrl = `${documentsUrl}/workshops/invalid-detail-fixture`

test.afterEach(async ({ request }) => {
  const removed = await request.delete(fixtureUrl, { headers: { Authorization: "Bearer owner" } })
  expect(removed.ok()).toBeTruthy()
})

test("malformed detail data exposes stable recovery copy rather than parser internals", async ({
  page,
  request,
}) => {
  const created = await request.patch(fixtureUrl, {
    headers: { Authorization: "Bearer owner" },
    data: { fields: { title: { stringValue: "Invalid detail fixture" } } },
  })
  expect(created.ok()).toBeTruthy()
  await page.goto("/workshops/invalid-detail-fixture")
  await expect(page.getByRole("alert")).toContainText("Workshop could not be loaded. Try again.")
  const removed = await request.delete(fixtureUrl, {
    headers: { Authorization: "Bearer owner" },
  })
  expect(removed.ok()).toBeTruthy()
  await page.getByRole("button", { name: "Try again" }).click()
  await expect(page.getByRole("alert")).toContainText(
    "This workshop does not exist or was removed.",
  )
})
