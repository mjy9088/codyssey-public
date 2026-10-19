import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";

const root = process.cwd();
const source = (path) => readFile(join(root, path), "utf8");

test("the portfolio keeps its static, modular source structure", async () => {
  const required = [
    "index.html",
    "css/style.css",
    "css/tokens.css",
    "css/base.css",
    "css/components.css",
    "css/layout.css",
    "js/app.js",
    "js/theme.js",
    "js/navigation.js",
    "js/projects.js",
    "js/contact.js",
    "images/profile-notes.svg",
  ];
  await Promise.all(required.map(async (path) => assert.ok((await readFile(join(root, path))).length > 0, `${path} must exist`)));

  const html = await source("index.html");
  assert.match(html, /<link[^>]+href=["']css\/style\.css["']/);
  assert.match(html, /<script[^>]+type=["']module["'][^>]+src=["']js\/app\.js["']/);

  const entryCss = await source("css/style.css");
  for (const stylesheet of ["tokens.css", "base.css", "components.css", "layout.css"])
    assert.match(entryCss, new RegExp(`@import\\s+url\\(["']${stylesheet.replace(".", "\\.")}["']\\)`));
});

test("responsive and interaction rules preserve the documented visual contract", async () => {
  const [layout, components, tokens] = await Promise.all([
    source("css/layout.css"),
    source("css/components.css"),
    source("css/tokens.css"),
  ]);
  assert.match(layout, /@media\s*\(min-width:\s*48rem\)/);
  assert.match(layout, /@media\s*\(min-width:\s*64rem\)/);
  assert.match(layout, /grid-template-columns:\s*repeat\(auto-fit,\s*minmax\(min\(100%,\s*18rem\),\s*1fr\)\)/);
  assert.match(tokens, /--shadow-paper:\s*[^;]+;/);
  const projectCard = components.match(/(?:^|\n)\.project-card\s*\{([^}]*)\}/s)?.[1] ?? "";
  const projectHover = components.match(/\.project-card:hover,\s*\.project-card:focus-within\s*\{([^}]*)\}/s)?.[1] ?? "";
  const button = components.match(/\.button\s*\{([^}]*)\}/s)?.[1] ?? "";
  assert.match(projectCard, /box-shadow:\s*var\(--shadow-paper\)/);
  assert.match(projectCard, /transition:[^;]*border-color[^;]*transform/);
  assert.match(projectHover, /transform:\s*translateY\(calc\(var\(--space-1\)\s*\*\s*-1\)\)/);
  assert.match(button, /transition:[^;]*background-color[^;]*border-color[^;]*color[^;]*transform/);
});

test("runtime behavior remains framework-free vanilla JavaScript", async () => {
  const packageJson = JSON.parse(await source("package.json"));
  assert.deepEqual(packageJson.dependencies ?? {}, {}, "the static site must not ship runtime packages");
  const forbidden = /^(?:react|react-dom|vue|svelte|angular|@angular\/|preact|solid-js|jquery)$/;
  for (const dependency of Object.keys(packageJson.devDependencies ?? {}))
    assert.doesNotMatch(dependency, forbidden, `${dependency} is a frontend runtime dependency`);

  const files = await readdir(join(root, "js"));
  assert.deepEqual(files.toSorted(), ["app.js", "contact.js", "navigation.js", "projects.js", "theme.js"]);
  const modules = await Promise.all(files.map((file) => source(`js/${file}`)));
  for (const moduleSource of modules) {
    for (const match of moduleSource.matchAll(/from\s+["']([^"']+)["']/g))
      assert.ok(match[1].startsWith("./"), `runtime import must be local: ${match[1]}`);
  }

  const [app, theme, navigation, projects, contact] = await Promise.all([
    source("js/app.js"),
    source("js/theme.js"),
    source("js/navigation.js"),
    source("js/projects.js"),
    source("js/contact.js"),
  ]);
  assert.match(app, /import\s+\{\s*initProjects\s*\}\s+from\s+["']\.\/projects\.js["']/);
  assert.match(theme, /localStorage\.(?:getItem|setItem)\(/);
  assert.match(navigation, /new\s+IntersectionObserver\(/);
  assert.match(navigation, /addEventListener\(["']scroll["']/);
  assert.match(projects, /await\s+fetch\(/);
  assert.match(projects, /\.textContent\s*=/);
  assert.match(contact, /addEventListener\(["']submit["']/);
});
