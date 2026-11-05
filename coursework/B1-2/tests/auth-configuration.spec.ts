import { expect, test } from "@playwright/test"
import { resetDocumentsUrl } from "./emulator-endpoints"

test.beforeEach(async ({ request }) => {
  const reset = await request.delete(resetDocumentsUrl)
  expect(reset.ok()).toBeTruthy()
})

for (const scenario of [
  { providerCode: "CONFIGURATION_NOT_FOUND", message: "Firebase Authentication is not configured" },
  { providerCode: "OPERATION_NOT_ALLOWED", message: "Anonymous sign-in is disabled" },
] as const) {
  for (const route of ["/workshops", "/workshops/new"]) {
    test(`${route} distinguishes ${scenario.providerCode} from network failure and can retry after setup`, async ({
      page,
    }) => {
      const signUp = "**/identitytoolkit.googleapis.com/v1/accounts:signUp**"
      await page.route(signUp, (request) =>
        request.fulfill({
          status: 400,
          json: {
            error: {
              code: 400,
              message: scenario.providerCode,
              errors: [{ message: scenario.providerCode, domain: "global", reason: "invalid" }],
            },
          },
        }),
      )
      await page.goto(route)
      await expect(page.getByRole("alert")).toContainText(scenario.message)
      await expect(page.getByRole("alert")).not.toContainText("Try again to reconnect")
      await expect(page.getByRole("button", { name: "Create workshop" })).toHaveCount(0)
      await page.unroute(signUp)
      await page.getByRole("button", { name: "Try again" }).click()
      if (route === "/workshops/new") {
        await expect(page.getByLabel("Workshop title")).toBeVisible()
      } else {
        await expect(page.getByText("The schedule is clear")).toBeVisible()
      }
      await expect(page.getByRole("alert")).toHaveCount(0)
    })
  }
}
