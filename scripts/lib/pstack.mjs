// @ts-check

import { constants, promises as fs } from "node:fs";
import path from "node:path";

export const PSTACK_VERSION = "0.15.32";
export const SOURCE_REVISION = "f51fdeba3d803ef90e4eaa4a95ffb4e76008ab37";
export const SOURCE_URL = "https://github.com/backnotprop/pstack.git";

export const APPROVED_SKILLS = Object.freeze([
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
]);

/** @typedef {{kind: "file", data: Buffer} | {kind: "directory", entries: ReadonlyMap<string, PassiveNode>}} PassiveNode */

class IncompleteRollbackError extends AggregateError {}

/** @param {string} root @param {string} label */
async function requireCanonicalDirectory(root, label) {
  if (!path.isAbsolute(root) || root !== path.resolve(root)) {
    throw new Error(`${label} must be an absolute canonical path: ${root}`);
  }
  const metadata = await fs.lstat(root);
  if (metadata.isSymbolicLink() || !metadata.isDirectory()) {
    throw new Error(`${label} must be a real directory, not a symbolic link: ${root}`);
  }
  if ((await fs.realpath(root)) !== root) {
    throw new Error(`${label} must not traverse symbolic links: ${root}`);
  }
}

/** @param {string} filePath */
async function readRegularFile(filePath) {
  const handle = await fs.open(filePath, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const metadata = await handle.stat();
    if (!metadata.isFile()) {
      throw new Error(`Expected a regular file: ${filePath}`);
    }
    return await handle.readFile();
  } finally {
    await handle.close();
  }
}

/** @param {string} entryPath @returns {Promise<PassiveNode>} */
async function readPassiveTree(entryPath) {
  const metadata = await fs.lstat(entryPath);
  if (metadata.isSymbolicLink()) {
    throw new Error(`Symbolic links are not allowed: ${entryPath}`);
  }
  if (metadata.isFile()) {
    return { kind: "file", data: await readRegularFile(entryPath) };
  }
  if (!metadata.isDirectory()) {
    throw new Error(`Expected a regular file or directory: ${entryPath}`);
  }
  /** @type {Map<string, PassiveNode>} */
  const entries = new Map();
  for (const name of (await fs.readdir(entryPath)).sort()) {
    entries.set(name, await readPassiveTree(path.join(entryPath, name)));
  }
  return { kind: "directory", entries };
}

/** @param {Buffer} document @param {string} expectedName */
function requireSkillName(document, expectedName) {
  const frontmatter = document.toString("utf8").match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
  const contents = frontmatter?.[1] ?? "";
  const declarations = [...contents.matchAll(/^name\s*:/gm)];
  const name = contents.match(/^name:\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9-]+))\s*$/m);
  const actualName = name?.[1] ?? name?.[2] ?? name?.[3];
  if (declarations.length !== 1 || actualName !== expectedName) {
    throw new Error(
      `SKILL.md frontmatter name must be ${expectedName}, got ${actualName ?? "none"}`,
    );
  }
}

/** @param {string} entryPath @param {"directory" | "file"} expectedKind */
async function validateExisting(entryPath, expectedKind, recursive = false) {
  let metadata;
  try {
    metadata = await fs.lstat(entryPath);
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return;
    throw error;
  }
  if (metadata.isSymbolicLink()) {
    throw new Error(`Destination symbolic links are not allowed: ${entryPath}`);
  }
  if (expectedKind === "file") {
    if (!metadata.isFile()) throw new Error(`Destination must be a regular file: ${entryPath}`);
    return;
  }
  if (!metadata.isDirectory()) throw new Error(`Destination must be a directory: ${entryPath}`);
  if (!recursive) return;
  for (const name of await fs.readdir(entryPath)) {
    const child = path.join(entryPath, name);
    const childMetadata = await fs.lstat(child);
    if (childMetadata.isSymbolicLink()) {
      throw new Error(`Destination symbolic links are not allowed: ${child}`);
    }
    if (childMetadata.isDirectory()) await validateExisting(child, "directory", true);
    else if (!childMetadata.isFile())
      throw new Error(`Destination must contain only regular files or directories: ${child}`);
  }
}

/** @param {PassiveNode} node @param {string} destination */
async function writePassiveTree(node, destination) {
  switch (node.kind) {
    case "file":
      await fs.writeFile(destination, node.data, { mode: 0o644, flag: "wx" });
      return;
    case "directory":
      await fs.mkdir(destination, { mode: 0o755 });
      for (const [name, child] of node.entries) {
        await writePassiveTree(child, path.join(destination, name));
      }
  }
}

/**
 * Install the reviewed pstack subset from an already checked-out source tree.
 * @param {string} sourceRoot absolute canonical pstack checkout path
 * @param {string} homeRoot absolute canonical user home path
 */
export async function installSkills(sourceRoot, homeRoot) {
  await requireCanonicalDirectory(sourceRoot, "sourceRoot");
  await requireCanonicalDirectory(homeRoot, "homeRoot");
  const sourceSkillsRoot = path.join(sourceRoot, "skills");
  await requireCanonicalDirectory(sourceSkillsRoot, "source skills root");

  /** @type {Map<string, PassiveNode>} */
  const selected = new Map();
  for (const name of APPROVED_SKILLS) {
    const tree = await readPassiveTree(path.join(sourceSkillsRoot, name));
    if (tree.kind !== "directory") throw new Error(`Selected skill must be a directory: ${name}`);
    const skillDocument = tree.entries.get("SKILL.md");
    if (!skillDocument || skillDocument.kind !== "file")
      throw new Error(`Selected skill is missing regular SKILL.md: ${name}`);
    requireSkillName(skillDocument.data, name);
    rejectNestedSkills(tree);
    selected.set(name, tree);
  }
  const license = await readPassiveTree(path.join(sourceRoot, "LICENSE"));
  if (license.kind !== "file") throw new Error("LICENSE must be a regular file");

  const agentsRoot = path.join(homeRoot, ".agents");
  const skillsRoot = path.join(agentsRoot, "skills");
  await validateExisting(agentsRoot, "directory");
  await validateExisting(skillsRoot, "directory");
  await fs.mkdir(agentsRoot, { recursive: true, mode: 0o700 });
  await fs.mkdir(skillsRoot, { recursive: true, mode: 0o700 });
  const lockRoot = path.join(skillsRoot, ".pstack-install.lock");
  try {
    await fs.mkdir(lockRoot, { mode: 0o700 });
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "EEXIST") {
      throw new Error(
        `Another installation or interrupted run owns ${lockRoot}; inspect recovery data before removing that lock`,
      );
    }
    throw error;
  }
  let retainLock = false;
  try {
    for (const name of APPROVED_SKILLS)
      await validateExisting(path.join(skillsRoot, name), "directory", true);
    await validateExisting(path.join(skillsRoot, "pstack.LICENSE"), "file");
    await replaceSkills(skillsRoot, selected, license);
  } catch (error) {
    retainLock = error instanceof IncompleteRollbackError;
    throw error;
  } finally {
    if (!retainLock) await fs.rmdir(lockRoot);
  }
}

/** @param {PassiveNode} node */
function rejectNestedSkills(node) {
  if (node.kind !== "directory") return;
  for (const [name, child] of node.entries) {
    if (child.kind !== "directory") continue;
    if (child.entries.has("SKILL.md")) {
      throw new Error(`Nested skill declarations are not approved: ${name}`);
    }
    rejectNestedSkills(child);
  }
}

/** @param {string} skillsRoot @param {ReadonlyMap<string, PassiveNode>} selected @param {PassiveNode} license */
async function replaceSkills(skillsRoot, selected, license) {
  const transactionRoot = await fs.mkdtemp(path.join(skillsRoot, ".pstack-install-"));
  await fs.chmod(transactionRoot, 0o700);
  const stagedRoot = path.join(transactionRoot, "staged");
  const backupRoot = path.join(transactionRoot, "backup");
  await fs.mkdir(stagedRoot, { mode: 0o700 });
  await fs.mkdir(backupRoot, { mode: 0o700 });

  /** @type {{target: string, backup: string, backedUp: boolean, installed: boolean}[]} */
  const changes = [];
  let retainRecovery = false;
  try {
    for (const [name, tree] of selected) await writePassiveTree(tree, path.join(stagedRoot, name));
    await writePassiveTree(license, path.join(stagedRoot, "pstack.LICENSE"));
    await fs.chmod(path.join(stagedRoot, "pstack.LICENSE"), 0o644);

    for (const name of [...APPROVED_SKILLS, "pstack.LICENSE"]) {
      const target = path.join(skillsRoot, name);
      const backup = path.join(backupRoot, name);
      const hadPrevious = await fs.lstat(target).then(
        () => true,
        (error) => {
          if (error instanceof Error && "code" in error && error.code === "ENOENT") return false;
          throw error;
        },
      );
      const change = { target, backup, backedUp: false, installed: false };
      changes.push(change);
      if (hadPrevious) {
        await fs.rename(target, backup);
        change.backedUp = true;
      }
      await fs.rename(path.join(stagedRoot, name), target);
      change.installed = true;
    }
  } catch (installationError) {
    /** @type {unknown[]} */
    const rollbackErrors = [];
    for (const change of changes.reverse()) {
      try {
        if (change.installed) await fs.rm(change.target, { recursive: true, force: true });
        if (change.backedUp) await fs.rename(change.backup, change.target);
      } catch (rollbackError) {
        rollbackErrors.push(rollbackError);
      }
    }
    if (rollbackErrors.length > 0) {
      retainRecovery = true;
      throw new IncompleteRollbackError(
        [installationError, ...rollbackErrors],
        `pstack rollback failed; recovery data retained at ${transactionRoot}`,
      );
    }
    throw installationError;
  } finally {
    if (!retainRecovery) await fs.rm(transactionRoot, { recursive: true, force: true });
  }
}
