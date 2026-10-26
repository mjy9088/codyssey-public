import { readdirSync, readFileSync } from "node:fs"
import { join } from "node:path"
import ts from "typescript"
import { describe, expect, it } from "vitest"
import { z } from "zod"

const root = process.cwd()
const src = join(root, "src")
const read = (path: string) => readFileSync(join(root, path), "utf8")
const tsxFiles = (directory: string) =>
  readdirSync(join(src, directory))
    .filter((file) => file.endsWith(".tsx"))
    .toSorted()

const parse = (path: string) =>
  ts.createSourceFile(path, read(path), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX)

const imports = (file: ts.SourceFile) =>
  file.statements
    .filter(ts.isImportDeclaration)
    .flatMap((statement) =>
      ts.isStringLiteral(statement.moduleSpecifier) ? [statement.moduleSpecifier.text] : [],
    )

const hasJsx = (node: ts.Node) => {
  let found = false
  const visit = (child: ts.Node) => {
    if (ts.isJsxElement(child) || ts.isJsxSelfClosingElement(child) || ts.isJsxFragment(child))
      found = true
    if (!found) ts.forEachChild(child, visit)
  }
  visit(node)
  return found
}

const exportedPropComponents = (path: string) => {
  const file = parse(path)
  let count = 0
  for (const statement of file.statements) {
    if (!ts.isVariableStatement(statement)) continue
    if (!statement.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword))
      continue
    for (const declaration of statement.declarationList.declarations) {
      const initializer = declaration.initializer
      if (
        !initializer ||
        (!ts.isArrowFunction(initializer) && !ts.isFunctionExpression(initializer))
      )
        continue
      if (initializer.parameters.length > 0 && hasJsx(initializer)) count += 1
    }
  }
  return count
}

describe("frontend source contracts", () => {
  it("pins React 19 for both runtime packages", () => {
    const packageJson = z
      .object({ dependencies: z.record(z.string(), z.string()) })
      .parse(JSON.parse(read("package.json")))
    expect(packageJson.dependencies.react).toMatch(/^19\./)
    expect(packageJson.dependencies["react-dom"]).toMatch(/^19\./)
  })

  it("keeps routes, pages, reusable components, and data hooks separated", () => {
    const pages = tsxFiles("pages")
    const components = tsxFiles("components")
    const hooks = readdirSync(join(src, "hooks"))
      .filter((file) => /^use.+\.ts$/.test(file))
      .toSorted()
    expect(pages).toHaveLength(7)
    expect(components.length).toBeGreaterThanOrEqual(8)
    expect(hooks).toEqual(expect.arrayContaining(["useWorkshop.ts", "useWorkshops.ts"]))

    for (const component of components) {
      const paths = imports(parse(`src/components/${component}`))
      expect(paths.some((path) => path.includes("/pages/") || path.includes("/hooks/"))).toBe(false)
    }
    for (const hook of hooks) {
      const paths = imports(parse(`src/hooks/${hook}`))
      expect(paths.some((path) => path.includes("/pages/") || path.includes("/components/"))).toBe(
        false,
      )
    }
  })

  it("defines all route screens in App and composes them through the shared layout", () => {
    const app = parse("src/App.tsx")
    const appText = app.getFullText()
    const pageImports = imports(app).filter((path) => path.startsWith("./pages/"))
    expect(pageImports).toHaveLength(7)
    expect(imports(app)).toContain("./components/AppLayout")
    expect(appText).toMatch(/<Route\s+element=\{<AppLayout\s*\/>\}>/)
    expect((appText.match(/<Route\b/g) ?? []).length).toBeGreaterThanOrEqual(8)
  })

  it("provides at least eight prop-driven reusable component exports", () => {
    const count = tsxFiles("components").reduce(
      (total, file) => total + exportedPropComponents(`src/components/${file}`),
      0,
    )
    expect(count).toBeGreaterThanOrEqual(8)
  })

  it("reuses shared page composition and hook-owned request state", () => {
    const pageSources = tsxFiles("pages").map((file) => parse(`src/pages/${file}`))
    const pageHeaderUsers = pageSources.filter((file) =>
      imports(file).includes("../components/PageHeader"),
    )
    const hookUsers = pageSources.filter((file) =>
      imports(file).some(
        (path) => path === "../hooks/useWorkshop" || path === "../hooks/useWorkshops",
      ),
    )
    expect(pageHeaderUsers.length).toBeGreaterThanOrEqual(3)
    expect(hookUsers.length).toBeGreaterThanOrEqual(2)

    for (const hook of ["useWorkshop", "useWorkshops"]) {
      const file = parse(`src/hooks/${hook}.ts`)
      const text = file.getFullText()
      expect(imports(file)).toContain("../context/AuthContext")
      expect(imports(file)).toContain("../lib/workshop-store")
      expect(text).toMatch(/useState</)
      expect(text).toMatch(/useEffect\(/)
    }
  })

  it("keeps deterministic fixture administration separate from production CRUD", () => {
    // Given: the workshop list page and the production Firestore store.
    const workshopsPage = parse("src/pages/WorkshopsPage.tsx")
    const workshopStore = parse("src/lib/workshop-store.ts")

    // When: their module dependencies and exports are inspected.
    const storeText = workshopStore.getFullText()

    // Then: the page uses the fixture module and CRUD owns no seeding dependency or export.
    expect(imports(workshopsPage)).toContain("../lib/workshop-seed")
    expect(storeText).not.toMatch(/\bseedWorkshops\b/)
    expect(storeText).not.toMatch(/\bwriteBatch\b/)
  })
})
