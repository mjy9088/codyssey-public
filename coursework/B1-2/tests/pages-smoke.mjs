import assert from "node:assert/strict"
import { once } from "node:events"
import { mkdir, readFile } from "node:fs/promises"
import { createServer } from "node:http"
import { extname, resolve, sep } from "node:path"
import { chromium, expect } from "@playwright/test"

assert.equal(process.argv.length, 4, "Usage: node tests/pages-smoke.mjs SITE_DIR EVIDENCE_DIR")
const root = resolve(process.argv[2])
const evidence = resolve(process.argv[3])
const prefix = process.env.PAGES_BASE_PATH ?? "/codyssey-public/"
const types = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".svg": "image/svg+xml",
}
await mkdir(evidence, { recursive: true })
const server = createServer(async (request, response) => {
  const pathname = new URL(request.url, "http://localhost").pathname
  if (!pathname.startsWith(prefix)) return response.writeHead(404).end()
  const file = resolve(
    root,
    pathname.slice(prefix.length) + (pathname.endsWith("/") ? "index.html" : ""),
  )
  if (!file.startsWith(root + sep)) return response.writeHead(404).end()
  try {
    const body = await readFile(file)
    response
      .writeHead(200, { "Content-Type": types[extname(file)] ?? "application/octet-stream" })
      .end(body)
  } catch (error) {
    if (error.code !== "ENOENT") throw error
    response.writeHead(404).end()
  }
})
server.listen(0, "127.0.0.1")
await once(server, "listening")
let browser
try {
  const address = server.address()
  assert(address && typeof address !== "string")
  const origin = `http://127.0.0.1:${address.port}`
  const base = origin + prefix
  browser = await chromium.launch()
  const context = await browser.newContext({ reducedMotion: "reduce" })
  // Given: a real static artifact, synthetic remote config, and no external network access.
  await context.route("**/*", (route) =>
    new URL(route.request().url()).origin === origin ? route.continue() : route.abort(),
  )
  const page = await context.newPage()
  const capture = async (name) => {
    await page.evaluate(() => {
      if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
      window.scrollTo(0, 0)
    })
    await page.screenshot({ path: `${evidence}/${name}.png`, fullPage: true })
  }
  const runtimeErrors = []
  const assetFailures = []
  page.on("pageerror", (error) => runtimeErrors.push(error.message))
  page.on("response", (response) => {
    if (/\.(js|css|svg)$/.test(response.url()) && !response.ok()) assetFailures.push(response.url())
  })
  for (const width of [375, 768, 1280]) {
    await page.setViewportSize({ width, height: 900 })
    // When: visitors follow the root's real links to both separate projects.
    await page.goto(base)
    await expect(page.getByRole("link", { name: "B1-1: Developer portfolio" })).toBeVisible()
    await capture(`index-${width}`)
    await page.getByRole("link", { name: "B1-1: Developer portfolio" }).click()
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible()
    assert.equal(new URL(page.url()).pathname, `${prefix}B1-1/`)
    await capture(`portfolio-${width}`)
    await page.getByRole("button", { name: /Switch to (light|dark) theme/ }).click()
    const theme = await page.locator("html").getAttribute("data-theme")
    await page.reload()
    assert.equal(await page.locator("html").getAttribute("data-theme"), theme)
    await page.goto(base)
    await page.getByRole("link", { name: "B1-2: Workshop planner" }).click()
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible()
    await capture(`home-${width}`)
    for (const route of [
      "workshops",
      "workshops/new",
      "workshops/synthetic",
      "workshops/synthetic/edit",
      "about",
      "missing",
    ]) {
      await page.goto(`${base}B1-2/#/${route}`)
      if (["workshops", "workshops/synthetic", "workshops/synthetic/edit"].includes(route)) {
        await expect(page.getByRole("alert")).toContainText("Authentication is unavailable")
      } else {
        await expect(page.getByRole("heading").first()).toBeVisible()
      }
      // Then: copied links and refreshes retain the hash route without server rewrites.
      await page.reload()
      assert.equal(new URL(page.url()).hash, `#/${route}`)
      await expect(page.locator("main")).toBeVisible()
      if (route === "workshops/new") {
        await page.getByRole("button", { name: "Create workshop" }).click()
        await expect(page.getByText("Use at least 3 characters.")).toBeVisible()
      }
      await expect
        .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
        .toBe(true)
      await capture(`${route.replaceAll("/", "-")}-${width}`)
    }
    await page.goto(`${base}B1-2/#/about`)
    await page.getByRole("link", { name: "Workshops", exact: true }).click()
    assert.equal(new URL(page.url()).hash, "#/workshops")
    await page.getByRole("link", { name: "Skip to main content" }).focus()
    await page.keyboard.press("Enter")
    await expect(page.locator("main")).toBeFocused()
    assert.equal(new URL(page.url()).hash, "#/workshops")
  }
  assert.deepEqual(runtimeErrors, [])
  assert.deepEqual(assetFailures, [])
  console.log(
    "Pages browser checks passed: both project prefixes, hash routes/reloads, validation, skip focus, 3 widths, no runtime/asset errors; external Firebase deliberately blocked",
  )
} finally {
  await browser?.close()
  await new Promise((done) => server.close(done))
}
