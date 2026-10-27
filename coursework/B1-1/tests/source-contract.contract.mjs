import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import test from "node:test";
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
  const forbiddenDomainGlobals = new Set([
    "window",
    "document",
    "localStorage",
    "fetch",
    "matchMedia",
    "HTMLElement",
    "HTMLInputElement",
    "HTMLTextAreaElement",
    "IntersectionObserver",
  ]);
  assert.ok(files.some((file) => relative(runtime, file).startsWith("domain/")));
  assert.ok(files.some((file) => relative(runtime, file).startsWith("data/")));
  assert.ok(files.some((file) => relative(runtime, file).startsWith("ui/")));

  for (const file of files) {
    const name = relative(runtime, file);
    const layer = name.split("/")[0];
    const tree = ts.createSourceFile(file, await readFile(file, "utf8"), ts.ScriptTarget.Latest);
    const inspect = (node) => {
      if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier)) {
        const specifier = node.moduleSpecifier.text;
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
      }
      if (layer === "domain" && ts.isIdentifier(node)) {
        assert.ok(!forbiddenDomainGlobals.has(node.text), `${name} depends on ${node.text}`);
      }
      if (layer === "ui" && ts.isCallExpression(node) && ts.isIdentifier(node.expression)) {
        assert.notEqual(node.expression.text, "fetch", `${name} owns an HTTP request`);
      }
      ts.forEachChild(node, inspect);
    };
    inspect(tree);
  }
});
