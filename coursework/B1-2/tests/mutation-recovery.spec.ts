import { readFileSync } from "node:fs"
import { type APIRequestContext, expect, test } from "@playwright/test"
import { resetDocumentsUrl, rulesUrl } from "./emulator-endpoints"

const baselineRules = readFileSync("firestore.rules", "utf8")
const deniedRules = readFileSync("tests/fixtures/firestore-deny-writes.rules", "utf8")
const installRules = async (request: APIRequestContext, content: string) => {
  const response = await request.put(rulesUrl, {
    data: { rules: { files: [{ name: "firestore.rules", content }] } },
  })
  expect(response.ok()).toBeTruthy()
}

test.beforeEach(async ({ request }) => {
  await installRules(request, baselineRules)
  const reset = await request.delete(resetDocumentsUrl)
  expect(reset.ok()).toBeTruthy()
})

test.afterEach(async ({ request }) => installRules(request, baselineRules))

for (const operation of ["create", "edit"] as const) {
  test(`${operation} preserves the draft and recovers after a real Firestore rejection`, async ({
    page,
    request,
  }) => {
    await page.goto("/workshops")
    await expect(page.getByText("The schedule is clear")).toBeVisible()
    if (operation === "edit") {
      await page.getByRole("button", { name: "Load sample schedule" }).click()
      await page.getByRole("searchbox", { name: "Search workshops" }).fill("denim")
      await page.getByRole("link", { name: "Patch visible denim", exact: true }).click()
      await page.getByRole("link", { name: "Edit", exact: true }).click()
    } else {
      await page.getByRole("link", { name: "Add workshop", exact: true }).click()
    }
    const title = `Recovered ${operation} workshop`
    await page.getByLabel("Workshop title").fill(title)
    await page.getByLabel("Summary").fill("A synthetic draft preserved through rejected writes.")
    await page.getByLabel("Facilitator").fill("Local Operator")
    await page.getByLabel("Location").fill("Test bench")
    await page.getByLabel("Start date and time").fill("2026-12-12T14:00")
    await page.getByLabel("Capacity").fill("8")
    await installRules(request, deniedRules)
    const submit = page.getByRole("button", {
      name: operation === "create" ? "Create workshop" : "Save changes",
    })
    await submit.click()
    await expect(page.getByRole("alert")).toHaveText("The workshop could not be saved. Try again.")
    await expect(submit).toBeEnabled()
    await expect(page.getByLabel("Workshop title")).toHaveValue(title)
    await expect(page.getByLabel("Capacity")).toHaveValue("8")
    await installRules(request, baselineRules)
    await submit.click()
    await expect(page.getByRole("heading", { level: 1, name: title, exact: true })).toBeVisible()
    await page.reload()
    await expect(page.getByRole("heading", { level: 1, name: title, exact: true })).toBeVisible()
    await page.goto("/workshops")
    await expect(
      page.getByText(operation === "create" ? "1 result" : "5 results", { exact: true }),
    ).toBeVisible()
    await page.getByRole("searchbox", { name: "Search workshops" }).fill(title)
    await expect(page.getByRole("link", { name: title, exact: true })).toHaveCount(1)
    await expect(page.getByText("1 result", { exact: true })).toBeVisible()
  })
}
