import { expect, test } from "@playwright/test"

const projectId = "benchbook-local"

test.beforeEach(async ({ request }) => {
  const response = await request.delete(
    `http://firebase:8080/emulator/v1/projects/${projectId}/databases/(default)/documents`,
  )
  expect(response.ok()).toBeTruthy()
})

test("creates, filters, edits, and deletes workshops through the real emulator", async ({
  page,
}) => {
  await page.goto("/workshops")
  await expect(page.getByText("The schedule is clear")).toBeVisible()
  await page.getByRole("button", { name: "Load sample schedule" }).click()
  await expect(page.getByText("5 results")).toBeVisible()

  await page.getByRole("searchbox", { name: "Search workshops" }).fill("denim")
  await expect(page.getByText("1 result")).toBeVisible()
  await page.getByRole("link", { name: "Patch visible denim" }).click()
  await expect(page.getByRole("heading", { name: "Patch visible denim" })).toBeVisible()

  await page.getByRole("link", { name: "Edit" }).click()
  await page.getByLabel("Workshop title").fill("Patch a denim jacket")
  await page.getByRole("button", { name: "Save changes" }).click()
  await expect(page.getByRole("heading", { name: "Patch a denim jacket" })).toBeVisible()

  await page.getByRole("button", { name: "Delete" }).click()
  await page.getByRole("button", { name: "Delete permanently" }).click()
  await expect(page.getByRole("heading", { name: "Workshop schedule" })).toBeVisible()
  await expect(page.getByText("4 results")).toBeVisible()
})

test("shows validation and creates a workshop from controlled input", async ({ page }) => {
  await page.goto("/workshops")
  await expect(page.getByText("The schedule is clear")).toBeVisible()
  await page.goto("/workshops/new")
  await page.getByRole("button", { name: "Create workshop" }).click()
  await expect(page.getByText("Use at least 3 characters.")).toBeVisible()
  await page.getByLabel("Workshop title").fill("Tune a hand plane")
  await page.getByLabel("Summary").fill("Set the blade and flatten a board edge safely.")
  await page.getByLabel("Facilitator").fill("Ari Moss")
  await page.getByLabel("Location").fill("Wood bench")
  await page.getByLabel("Start date and time").fill("2026-11-12T18:30")
  await page.getByLabel("Capacity").fill("9")
  await page.getByRole("button", { name: "Create workshop" }).click()
  await expect(page.getByRole("heading", { level: 1, name: "Tune a hand plane" })).toBeVisible()
})

test("persists workshop CRUD across browser reloads", async ({ page }) => {
  // Given: a workshop created through the signed-in application and real emulators.
  await page.goto("/workshops")
  await expect(page.getByText("The schedule is clear")).toBeVisible()
  await page.goto("/workshops/new")
  await page.getByLabel("Workshop title").fill("Build a synthetic test jig")
  await page
    .getByLabel("Summary")
    .fill("Assemble a deterministic fixture for local emulator verification.")
  await page.getByLabel("Facilitator").fill("Test Operator")
  await page.getByLabel("Location").fill("Local bench")
  await page.getByLabel("Start date and time").fill("2026-12-10T14:00")
  await page.getByLabel("Capacity").fill("6")
  await page.getByRole("button", { name: "Create workshop" }).click()
  await expect(
    page.getByRole("heading", { level: 1, name: "Build a synthetic test jig" }),
  ).toBeVisible()

  // When: the browser reloads after create and update operations.
  await page.reload()
  await expect(
    page.getByRole("heading", { level: 1, name: "Build a synthetic test jig" }),
  ).toBeVisible()
  await page.getByRole("link", { name: "Edit" }).click()
  await page.getByLabel("Workshop title").fill("Build a persisted test jig")
  await page.getByRole("button", { name: "Save changes" }).click()
  await expect(
    page.getByRole("heading", { level: 1, name: "Build a persisted test jig" }),
  ).toBeVisible()
  await page.reload()

  // Then: Firestore retains the updated record and deletion survives another reload.
  await expect(
    page.getByRole("heading", { level: 1, name: "Build a persisted test jig" }),
  ).toBeVisible()
  await page.getByRole("button", { name: "Delete" }).click()
  await page.getByRole("button", { name: "Delete permanently" }).click()
  await expect(page.getByText("The schedule is clear")).toBeVisible()
  await page.reload()
  await expect(page.getByText("The schedule is clear")).toBeVisible()
})

test("shows a concise recovery message when stored workshop data is invalid", async ({
  page,
  request,
}) => {
  // Given: Firestore contains a document that fails the application's boundary schema.
  const response = await request.patch(
    `http://firebase:8080/v1/projects/${projectId}/databases/(default)/documents/workshops/malformed-fixture`,
    {
      headers: { Authorization: "Bearer owner" },
      data: {
        fields: {
          startsAt: { stringValue: "2026-12-01T10:00" },
          title: { stringValue: "Malformed fixture" },
        },
      },
    },
  )
  expect(response.ok()).toBeTruthy()

  // When: the list parses data returned by the real Firestore emulator.
  await page.goto("/workshops")

  // Then: implementation details are hidden behind an actionable UI message.
  await expect(page.getByRole("alert")).toContainText("Workshops could not be loaded.")
  await expect(page.getByRole("button", { name: "Try again" })).toBeVisible()

  // Given: the invalid fixture is removed through the emulator administration endpoint.
  const cleanupResponse = await request.delete(
    `http://firebase:8080/v1/projects/${projectId}/databases/(default)/documents/workshops/malformed-fixture`,
    { headers: { Authorization: "Bearer owner" } },
  )
  expect(cleanupResponse.ok()).toBeTruthy()

  // When: the user retries the failed SDK-backed read.
  await page.getByRole("button", { name: "Try again" }).click()

  // Then: the application recovers without a reload or production-code shortcut.
  await expect(page.getByText("The schedule is clear")).toBeVisible()
})

test("all primary routes and the recovery route render", async ({ page }) => {
  for (const route of ["/", "/workshops", "/workshops/new", "/about", "/missing"]) {
    await page.goto(route)
    await expect(page.locator("main")).toBeVisible()
  }
  await expect(page.getByText("This bench is empty")).toBeVisible()
})
