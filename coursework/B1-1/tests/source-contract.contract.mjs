import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";
import ts from "typescript";

const root = process.cwd();
const runtime = join(root, "js");

const sourcesIn = async (directory) => {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name);
      return entry.isDirectory() ? sourcesIn(path) : path.endsWith(".js") ? [path] : [];
    }),
  );
  return files.flat();
};

test("published static entry points remain available without runtime dependencies", async () => {
  const html = await readFile(join(root, "index.html"), "utf8");
  assert.match(html, /<link[^>]+href=["']css\/style\.css["']/);
  assert.match(html, /<script[^>]+type=["']module["'][^>]+src=["']js\/app\.js["']/);
  const manifest = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
  assert.deepEqual(manifest.dependencies ?? {}, {});
  await Promise.all(["css/style.css", "js/app.js"].map((path) => readFile(join(root, path))));
});

test("neutral base CSS has no project token or component dependency", async () => {
  const base = await readFile(join(root, "css/base.css"), "utf8");
  assert.doesNotMatch(base, /@import\b/);
  assert.doesNotMatch(base, /var\s*\(\s*--/);
  assert.doesNotMatch(base, /\.[a-zA-Z_][\w-]*/);
});

test("runtime imports respect domain, data and presentation dependency direction", async () => {
  const files = await sourcesIn(runtime);
  const available = new Set(files.map((file) => resolve(file)));
  const program = ts.createProgram(files, { allowJs: true, noEmit: true });
  const checker = program.getTypeChecker();
  const forbiddenDomainGlobals = new Set([
    "window",
    "document",
    "localStorage",
    "sessionStorage",
    "globalThis",
    "navigator",
    "location",
    "history",
    "screen",
    "fetch",
    "matchMedia",
    "HTMLElement",
    "HTMLInputElement",
    "HTMLTextAreaElement",
    "IntersectionObserver",
    "MutationObserver",
    "ResizeObserver",
  ]);
  assert.ok(files.some((file) => relative(runtime, file).startsWith("domain/")));
  assert.ok(files.some((file) => relative(runtime, file).startsWith("data/")));
  assert.ok(files.some((file) => relative(runtime, file).startsWith("ui/")));

  for (const file of files) {
    const name = relative(runtime, file);
    const layer = name.split("/")[0];
    const tree = program.getSourceFile(file);
    assert.ok(tree, `${name} must be part of the runtime program`);
    const checkDependency = (specifier) => {
      assert.ok(specifier.startsWith("."), `${name} must not import a runtime package`);
      const target = resolve(dirname(file), specifier);
      assert.ok(available.has(target), `${name}: import must resolve inside the runtime tree`);
      const dependency = relative(runtime, target).split("/")[0];
      if (layer === "domain")
        assert.equal(dependency, "domain", `${name} crosses the domain boundary`);
      if (layer === "data")
        assert.ok(["domain", "data"].includes(dependency), `${name} imports presentation`);
      if (layer === "ui")
        assert.ok(
          ["domain", "ui"].includes(dependency),
          `${name} must receive I/O through composition`,
        );
    };
    const inspect = (node) => {
      if ((ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) && node.moduleSpecifier) {
        assert.ok(ts.isStringLiteral(node.moduleSpecifier), `${name} has an opaque module edge`);
        checkDependency(node.moduleSpecifier.text);
      }
      if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) {
        const specifier = node.arguments[0];
        assert.ok(specifier && ts.isStringLiteralLike(specifier), `${name} has an opaque import`);
        checkDependency(specifier.text);
      }
      if (ts.isIdentifier(node)) {
        const declarations = checker.getSymbolAtLocation(node)?.declarations ?? [];
        const local = declarations.some((entry) =>
          available.has(resolve(entry.getSourceFile().fileName)),
        );
        if (layer === "domain" && !local) {
          assert.ok(!forbiddenDomainGlobals.has(node.text), `${name} depends on ${node.text}`);
        }
        if (layer === "ui" && !local) {
          assert.ok(
            !["fetch", "localStorage", "sessionStorage"].includes(node.text),
            `${name} owns environmental I/O: ${node.text}`,
          );
        }
      }
      ts.forEachChild(node, inspect);
    };
    inspect(tree);
  }
});

test("every discovered domain module imports with browser capabilities poisoned", async () => {
  const files = await sourcesIn(join(runtime, "domain"));
  const result = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `const modules = JSON.parse(process.argv[1]);
       for (const name of ["window", "document", "localStorage", "sessionStorage", "fetch",
         "matchMedia", "navigator", "location", "history", "screen", "HTMLElement",
         "HTMLInputElement", "HTMLTextAreaElement", "IntersectionObserver", "MutationObserver",
         "ResizeObserver"]) {
         Object.defineProperty(globalThis, name, { configurable: true, get() {
           throw new Error("Domain import accessed browser capability: " + name);
         }});
       }
       for (const module of modules) await import(module);`,
      JSON.stringify(files.map((file) => pathToFileURL(file).href)),
    ],
    { encoding: "utf8", timeout: 10000 },
  );
  assert.equal(result.status, 0, result.stderr || result.error?.message);
});
