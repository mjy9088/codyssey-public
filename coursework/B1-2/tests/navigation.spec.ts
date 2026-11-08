import { expect, test } from "@playwright/test"

test("primary navigation marks only the exact current page", async ({ page }) => {
  for (const [route, current] of [
    ["/workshops", "Workshops"],
    ["/workshops/new", "Add"],
    ["/about", "About"],
    ["/workshops/missing-navigation-workshop", null],
    ["/workshops/missing-navigation-workshop/edit", null],
    ["/missing", null],
    ["/", null],
  ] as const) {
    await page.goto(route)
    const links = page
      .getByRole("navigation", { name: "Primary navigation" })
      .locator('[aria-current="page"]')
    await expect(links).toHaveCount(current === null ? 0 : 1)
    if (current !== null) await expect(links).toHaveText(current)
  }
})

test("the create route offers authentication recovery before accepting a draft", async ({
  page,
}) => {
  const signUpRequest = "**/identitytoolkit.googleapis.com/v1/accounts:signUp**"
  await page.route(signUpRequest, (route) => route.abort("failed"))
  await page.goto("/workshops/new")
  await expect(page.getByRole("alert")).toContainText("Authentication is unavailable")
  await expect(page.getByLabel("Workshop title")).toHaveCount(0)
  await page.unroute(signUpRequest)
  await page.getByRole("button", { name: "Try again" }).click()
  await expect(page.getByLabel("Workshop title")).toBeVisible()
  await expect(page.getByRole("button", { name: "Create workshop" })).toBeEnabled()
})
