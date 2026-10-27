// @ts-check

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { APPROVED_SKILLS, installSkills } from "../scripts/lib/pstack.mjs";

const EXPECTED_SKILLS = [
  "architect",
  "how",
  "why",
  "arena",
  "interrogate",
  "tdd",
  "principle-attack-the-premise",
  "principle-boundary-discipline",
  "principle-build-the-lever",
  "principle-encode-lessons-in-structure",
  "principle-exhaust-the-design-space",
  "principle-experience-first",
  "principle-explain-the-number",
  "principle-fix-root-causes",
  "principle-foundational-thinking",
  "principle-guard-the-context-window",
  "principle-laziness-protocol",
  "principle-make-operations-idempotent",
  "principle-migrate-callers-then-delete-legacy-apis",
  "principle-minimize-reader-load",
  "principle-model-the-domain",
  "principle-never-block-on-the-human",
  "principle-outcome-oriented-execution",
  "principle-prove-it-works",
  "principle-redesign-from-first-principles",
  "principle-separate-before-serializing-shared-state",
  "principle-sequence-verifiable-units",
  "principle-subtract-before-you-add",
  "principle-test-behavior-not-implementation",
  "principle-type-system-discipline",
];

/** @returns {Promise<{root: string, source: string, home: string}>} */
async function fixture() {
  const root = await fs.realpath(await fs.mkdtemp(path.join(tmpdir(), "pstack-test-")));
  const source = path.join(root, "source");
  const home = path.join(root, "home");
  await fs.mkdir(path.join(source, "skills"), { recursive: true });
  await fs.mkdir(home);
  await fs.writeFile(path.join(source, "LICENSE"), "fixture license\n", {
    mode: 0o600,
  });
  for (const name of APPROVED_SKILLS) {
    const skillRoot = path.join(source, "skills", name);
    await fs.mkdir(path.join(skillRoot, "references"), { recursive: true });
    await fs.writeFile(path.join(skillRoot, "SKILL.md"), `---\nname: ${name}\n---\n${name}\n`);
    await fs.writeFile(path.join(skillRoot, "references", "data.bin"), Buffer.from([0, 1, 2, 255]));
  }
  await fs.mkdir(path.join(source, "skills", "ignored-upstream"));
  await fs.writeFile(path.join(source, "skills", "ignored-upstream", "SKILL.md"), "ignored\n");
  return { root, source, home };
}

/** @param {string} socketPath @returns {Promise<import("node:net").Server>} */
async function listenOn(socketPath) {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(socketPath, resolve);
  });
  return server;
}

test("approved skill names are the reviewed 30-name set", () => {
  assert.deepEqual(APPROVED_SKILLS, EXPECTED_SKILLS);
});

test("installSkills copies passive bytes, replaces owned names, and preserves others", async (t) => {
  const { root, source, home } = await fixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const skillsRoot = path.join(home, ".agents", "skills");
  await fs.mkdir(path.join(skillsRoot, "architect"), { recursive: true });
  await fs.writeFile(path.join(skillsRoot, "architect", "old.txt"), "old\n");
  await fs.mkdir(path.join(skillsRoot, "user-skill"));
  await fs.writeFile(path.join(skillsRoot, "user-skill", "keep.txt"), "keep\n");

  await installSkills(source, home);

  assert.equal(
    await fs.readFile(path.join(skillsRoot, "architect", "SKILL.md"), "utf8"),
    "---\nname: architect\n---\narchitect\n",
  );
  assert.deepEqual(
    await fs.readFile(path.join(skillsRoot, "why", "references", "data.bin")),
    Buffer.from([0, 1, 2, 255]),
  );
  assert.equal(
    await fs.readFile(path.join(skillsRoot, "user-skill", "keep.txt"), "utf8"),
    "keep\n",
  );
  assert.equal(
    await fs.readFile(path.join(skillsRoot, "pstack.LICENSE"), "utf8"),
    "fixture license\n",
  );
  await assert.rejects(fs.access(path.join(skillsRoot, "architect", "old.txt")));
  await assert.rejects(fs.access(path.join(skillsRoot, "ignored-upstream")));
  assert.equal((await fs.stat(path.join(skillsRoot, "pstack.LICENSE"))).mode & 0o777, 0o644);
});

test("invalid selected source is rejected before destination writes", async (t) => {
  const { root, source, home } = await fixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await fs.rm(path.join(source, "skills", "tdd", "SKILL.md"));

  await assert.rejects(installSkills(source, home), /SKILL\.md/);

  await assert.rejects(fs.access(path.join(home, ".agents")));
});

test("missing and mismatched frontmatter names are rejected before writes", async (t) => {
  const first = await fixture();
  const second = await fixture();
  t.after(() =>
    Promise.all(
      [first.root, second.root].map((root) => fs.rm(root, { recursive: true, force: true })),
    ),
  );
  await fs.writeFile(
    path.join(first.source, "skills", "tdd", "SKILL.md"),
    "---\ndescription: no name\n---\n",
  );
  await fs.writeFile(
    path.join(second.source, "skills", "tdd", "SKILL.md"),
    "---\nname: wrong\n---\n",
  );

  await assert.rejects(installSkills(first.source, first.home), /frontmatter name/);
  await assert.rejects(installSkills(second.source, second.home), /frontmatter name/);

  await assert.rejects(fs.access(path.join(first.home, ".agents")));
  await assert.rejects(fs.access(path.join(second.home, ".agents")));
});

test("duplicate frontmatter names and nested skills are rejected before writes", async (t) => {
  const duplicate = await fixture();
  const nested = await fixture();
  t.after(() =>
    Promise.all(
      [duplicate.root, nested.root].map((root) => fs.rm(root, { recursive: true, force: true })),
    ),
  );
  await fs.writeFile(
    path.join(duplicate.source, "skills", "tdd", "SKILL.md"),
    "---\nname: tdd\nname: tdd\n---\n",
  );
  const nestedRoot = path.join(nested.source, "skills", "tdd", "references", "nested");
  await fs.mkdir(nestedRoot);
  await fs.writeFile(path.join(nestedRoot, "SKILL.md"), "---\nname: nested\n---\n");

  await assert.rejects(installSkills(duplicate.source, duplicate.home), /frontmatter name/);
  await assert.rejects(installSkills(nested.source, nested.home), /Nested skill declarations/);

  await assert.rejects(fs.access(path.join(duplicate.home, ".agents")));
  await assert.rejects(fs.access(path.join(nested.home, ".agents")));
});

test("CLI help and bad arguments finish before HOME or Git access", () => {
  const cli = path.resolve("scripts/setup-pstack.mjs");
  const environment = { HOME: "/path/that/does/not/exist", PATH: "" };

  const help = spawnSync(process.execPath, [cli, "--help"], {
    encoding: "utf8",
    env: environment,
  });
  const badArguments = spawnSync(process.execPath, [cli, "unexpected"], {
    encoding: "utf8",
    env: environment,
  });

  assert.equal(help.status, 0);
  assert.match(help.stdout, /^Usage: sh scripts\/setup-pstack\.sh/m);
  assert.equal(help.stderr, "");
  assert.equal(badArguments.status, 2);
  assert.equal(badArguments.stdout, "");
  assert.equal(badArguments.stderr, "Unexpected arguments; use --help\n");
});

test("source roots and selected source trees reject symlinks", async (t) => {
  const first = await fixture();
  const sourceLink = path.join(first.root, "source-link");
  await fs.symlink(first.source, sourceLink);
  await assert.rejects(installSkills(sourceLink, first.home), /canonical|symbolic link/);
  await assert.rejects(fs.access(path.join(first.home, ".agents")));

  const second = await fixture();
  t.after(() =>
    Promise.all(
      [first.root, second.root].map((root) => fs.rm(root, { recursive: true, force: true })),
    ),
  );
  const linkedFile = path.join(second.source, "skills", "architect", "references", "linked.md");
  await fs.symlink(path.join(second.source, "LICENSE"), linkedFile);
  await assert.rejects(installSkills(second.source, second.home), /symbolic link|regular/i);
  await assert.rejects(fs.access(path.join(second.home, ".agents")));
});

test("destination roots and selected destination trees reject symlinks", async (t) => {
  const first = await fixture();
  await fs.mkdir(path.join(first.home, "elsewhere"));
  await fs.symlink(path.join(first.home, "elsewhere"), path.join(first.home, ".agents"));
  await assert.rejects(installSkills(first.source, first.home), /symbolic link/);

  const second = await fixture();
  t.after(() =>
    Promise.all(
      [first.root, second.root].map((root) => fs.rm(root, { recursive: true, force: true })),
    ),
  );
  const skillsRoot = path.join(second.home, ".agents", "skills");
  await fs.mkdir(path.join(skillsRoot, "architect"), { recursive: true });
  await fs.symlink(path.join(second.home, "outside"), path.join(skillsRoot, "architect", "escape"));
  await assert.rejects(installSkills(second.source, second.home), /symbolic link/);
  assert.deepEqual(await fs.readdir(skillsRoot), ["architect"]);
});

test("non-regular source and destination entries are rejected", async (t) => {
  const first = await fixture();
  const sourceSocket = path.join(first.source, "skills", "architect", "bad.sock");
  const sourceServer = await listenOn(sourceSocket);
  await assert.rejects(installSkills(first.source, first.home), /regular file|directory/);
  await new Promise((resolve) => sourceServer.close(resolve));

  const second = await fixture();
  t.after(() =>
    Promise.all(
      [first.root, second.root].map((root) => fs.rm(root, { recursive: true, force: true })),
    ),
  );
  const destination = path.join(second.home, ".agents", "skills", "architect");
  await fs.mkdir(destination, { recursive: true });
  const destinationServer = await listenOn(path.join(destination, "bad.sock"));
  t.after(() => destinationServer.close());
  await assert.rejects(installSkills(second.source, second.home), /regular file|directory/);
});

test("replacement failure restores prior skills and removes transaction data", async (t) => {
  const { root, source, home } = await fixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const skillsRoot = path.join(home, ".agents", "skills");
  for (const name of ["architect", "how"]) {
    await fs.mkdir(path.join(skillsRoot, name), { recursive: true });
    await fs.writeFile(path.join(skillsRoot, name, "old.txt"), `${name} old\n`);
  }
  const rename = fs.rename.bind(fs);
  t.mock.method(fs, "rename", async (from, to) => {
    if (String(from).includes("/staged/how") && to === path.join(skillsRoot, "how")) {
      throw new Error("injected replacement failure");
    }
    return rename(from, to);
  });

  await assert.rejects(installSkills(source, home), /injected replacement failure/);

  assert.equal(
    await fs.readFile(path.join(skillsRoot, "architect", "old.txt"), "utf8"),
    "architect old\n",
  );
  assert.equal(await fs.readFile(path.join(skillsRoot, "how", "old.txt"), "utf8"), "how old\n");
  assert.deepEqual((await fs.readdir(skillsRoot)).sort(), ["architect", "how"]);
});

test("unselected user links are not inspected or replaced", async (t) => {
  const { root, source, home } = await fixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const skillsRoot = path.join(home, ".agents", "skills");
  await fs.mkdir(skillsRoot, { recursive: true });
  const link = path.join(skillsRoot, "user-skill");
  await fs.symlink(path.join(home, "not-ours"), link);
  await installSkills(source, home);
  assert.equal(await fs.readlink(link), path.join(home, "not-ours"));
});

test("failed rollback retains recovery data and blocks reinstallation", async (t) => {
  const { root, source, home } = await fixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const skillsRoot = path.join(home, ".agents", "skills");
  await fs.mkdir(path.join(skillsRoot, "architect"), { recursive: true });
  await fs.writeFile(path.join(skillsRoot, "architect", "old.txt"), "preserve me");
  const rename = fs.rename.bind(fs);
  t.mock.method(fs, "rename", async (from, to) => {
    if (String(from).endsWith("/staged/how") || String(from).endsWith("/backup/architect")) {
      throw new Error("injected recovery failure");
    }
    return rename(from, to);
  });
  await assert.rejects(installSkills(source, home), AggregateError);
  const recovery = (await fs.readdir(skillsRoot)).filter((name) =>
    name.startsWith(".pstack-install-"),
  );
  assert.equal(recovery.length, 1);
  assert.equal(
    await fs.readFile(path.join(skillsRoot, recovery[0], "backup", "architect", "old.txt"), "utf8"),
    "preserve me",
  );
  await assert.rejects(installSkills(source, home), /owns.*pstack-install\.lock/);
});

test("concurrent installers cannot interleave global replacements", async (t) => {
  const { root, source, home } = await fixture();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  let release;
  let entered;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const ready = new Promise((resolve) => {
    entered = resolve;
  });
  const rename = fs.rename.bind(fs);
  let held = false;
  t.mock.method(fs, "rename", async (from, to) => {
    if (!held && String(from).endsWith("/staged/architect")) {
      held = true;
      entered();
      await gate;
    }
    return rename(from, to);
  });
  const first = installSkills(source, home);
  await ready;
  try {
    await assert.rejects(installSkills(source, home), /owns.*pstack-install\.lock/);
  } finally {
    release();
  }
  await first;
  await assert.rejects(fs.access(path.join(home, ".agents", "skills", ".pstack-install.lock")));
});
