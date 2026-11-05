import { readFileSync } from "node:fs"
import { expect, test } from "@playwright/test"
import { resetDocumentsUrl, rulesUrl } from "./emulator-endpoints"

test.beforeEach(async ({ request }) => {
  const restored = await request.put(rulesUrl, {
    data: {
      rules: {
        files: [{ name: "firestore.rules", content: readFileSync("firestore.rules", "utf8") }],
      },
    },
  })
  expect(restored.ok()).toBeTruthy()
  const reset = await request.delete(resetDocumentsUrl)
  expect(reset.ok()).toBeTruthy()
})

test("double activation of create persists exactly one workshop", async ({ page }) => {
  await page.goto("/workshops/new")
  await page.getByLabel("Workshop title").fill("Namespaced repeated-submit fixture")
  await page
    .getByLabel("Summary")
    .fill("Disposable input for real duplicate-submission verification.")
  await page.getByLabel("Facilitator").fill("Synthetic Operator")
  await page.getByLabel("Location").fill("Emulator bench")
  await page.getByLabel("Start date and time").fill("2026-12-12T14:00")
  await page.getByLabel("Capacity").fill("8")
  await page.getByRole("button", { name: "Create workshop" }).dblclick()
  await expect(
    page.getByRole("heading", { level: 1, name: "Namespaced repeated-submit fixture" }),
  ).toBeVisible()
  await page.goto("/workshops")
  await expect(page.getByText("1 result", { exact: true })).toBeVisible()
  await page.reload()
  await expect(
    page.getByRole("link", { name: "Namespaced repeated-submit fixture", exact: true }),
  ).toHaveCount(1)
  await expect(page.getByText("1 result", { exact: true })).toBeVisible()
})
