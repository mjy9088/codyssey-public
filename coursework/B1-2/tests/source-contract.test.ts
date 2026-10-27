import { readdirSync, readFileSync } from "node:fs"
import { join, posix } from "node:path"
import ts from "typescript"
import { describe, expect, it } from "vitest"
import { z } from "zod"

const root = process.cwd()
const read = (path: string) => readFileSync(join(root, path), "utf8")
const sourceFiles = (directory: string): readonly string[] =>
  readdirSync(join(root, directory), { withFileTypes: true }).flatMap((entry) => {
    const path = `${directory}/${entry.name}`
    return entry.isDirectory() ? sourceFiles(path) : /\.tsx?$/.test(entry.name) ? [path] : []
  })

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
      .object({ dependencies: z.object({ react: z.string(), "react-dom": z.string() }) })
      .parse(JSON.parse(read("package.json")))
    expect(packageJson.dependencies.react).toMatch(/^19\./)
    expect(packageJson.dependencies["react-dom"]).toMatch(/^19\./)
  })

  it("keeps component, request-state, and adapter dependencies pointed away from pages", () => {
    for (const file of sourceFiles("src")) {
      for (const dependency of imports(parse(file))) {
        const target = dependency.startsWith(".")
          ? posix.normalize(posix.join(posix.dirname(file), dependency))
          : dependency
        if (file.startsWith("src/components/")) {
          expect(target, `${file} imports ${target}`).not.toMatch(/^src\/(pages|hooks)\//)
          expect(target, `${file} imports ${target}`).not.toMatch(
            /^src\/lib\/(firebase|workshop-store|workshop-seed)$/,
          )
        }
        if (file.startsWith("src/hooks/") || file.startsWith("src/lib/")) {
          expect(target, `${file} imports ${target}`).not.toMatch(/^src\/(pages|components)\//)
        }
      }
    }
  })

  it("keeps workshop rules independent of UI and Firebase initialization", () => {
    const domain = parse("src/lib/workshop.ts")
    expect(
      imports(domain).some((path) => /firebase|react|workshop-store|workshop-seed/.test(path)),
    ).toBe(false)
    const browserGlobals: string[] = []
    const visit = (node: ts.Node) => {
      if (
        ts.isIdentifier(node) &&
        ["window", "document", "localStorage", "navigator"].includes(node.text)
      )
        browserGlobals.push(node.text)
      ts.forEachChild(node, visit)
    }
    visit(domain)
    expect(browserGlobals).toEqual([])
  })

  it("provides at least eight prop-driven reusable component exports", () => {
    const count = sourceFiles("src/components").reduce(
      (total, file) => total + exportedPropComponents(file),
      0,
    )
    expect(count).toBeGreaterThanOrEqual(8)
  })

  it("keeps deterministic fixture administration separate from production CRUD", () => {
    // Given: the workshop list page and the production Firestore store.
    const workshopsPage = parse("src/pages/WorkshopsPage.tsx")
    const workshopStore = parse("src/lib/workshop-store.ts")

    // When: their module dependencies and exports are inspected.
    const storeImports = imports(workshopStore)

    // Then: the page uses the fixture module and CRUD owns no seeding dependency or export.
    expect(imports(workshopsPage)).toContain("../lib/workshop-seed")
    expect(storeImports.some((path) => /workshop-seed|fixtures/.test(path))).toBe(false)
  })
})
