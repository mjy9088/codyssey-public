#!/usr/bin/env node
// @ts-check

import { promises as fs } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

import { installSkills, PSTACK_VERSION, SOURCE_REVISION, SOURCE_URL } from "./lib/pstack.mjs";

const HELP = `Usage: sh scripts/setup-pstack.sh
Installs the reviewed pstack ${PSTACK_VERSION} skill subset for OpenCode.
Requires Git and Node.js 22+; writes selected user-level skills under ~/.agents/skills.
The installer downloads only ${SOURCE_URL} at ${SOURCE_REVISION}.`;

/**
 * @param {readonly string[]} arguments_
 * @param {Record<string, string> & {HOME: string}} environment
 * @returns {Promise<string>}
 */
function runGit(arguments_, environment) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "git",
      [
        "-c",
        "core.hooksPath=/dev/null",
        "-c",
        "init.templateDir=",
        "-c",
        "credential.helper=",
        "-c",
        "protocol.ext.allow=never",
        "-c",
        "protocol.file.allow=never",
        ...arguments_,
      ],
      {
        cwd: environment.HOME,
        env: environment,
        stdio: ["ignore", "pipe", "pipe"],
        windowsHide: true,
      },
    );
    /** @type {Buffer[]} */
    const stdout = [];
    /** @type {Buffer[]} */
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.once("error", reject);
    child.once("close", (code, signal) => {
      if (code === 0) {
        resolve(Buffer.concat(stdout).toString("utf8"));
        return;
      }
      const detail = Buffer.concat(stderr).toString("utf8").trim();
      reject(new Error(`git exited ${signal ?? code}${detail ? `: ${detail}` : ""}`));
    });
  });
}

async function main() {
  const arguments_ = process.argv.slice(2);
  if (arguments_.length === 1 && arguments_[0] === "--help") {
    process.stdout.write(`${HELP}\n`);
    return;
  }
  if (arguments_.length !== 0) {
    process.stderr.write("Unexpected arguments; use --help\n");
    process.exitCode = 2;
    return;
  }
  if (Number.parseInt(process.versions.node, 10) < 22) {
    throw new Error(`Node.js 22 or newer is required; found ${process.version}`);
  }
  const configuredHome = process.env.HOME;
  if (!configuredHome) throw new Error("HOME is not set");
  const homeRoot = await fs.realpath(configuredHome);
  if (
    !path.isAbsolute(configuredHome) ||
    path.resolve(configuredHome) !== configuredHome ||
    homeRoot !== configuredHome
  ) {
    throw new Error(`HOME must be an absolute canonical directory: ${configuredHome}`);
  }

  const temporaryRoot = await fs.mkdtemp(path.join(await fs.realpath(tmpdir()), "pstack-"));
  await fs.chmod(temporaryRoot, 0o700);
  const temporaryHome = path.join(temporaryRoot, "home");
  const sourceRoot = path.join(temporaryRoot, "source");
  await fs.mkdir(temporaryHome, { mode: 0o700 });
  const gitEnvironment = {
    PATH: process.env.PATH ?? "",
    HOME: temporaryHome,
    XDG_CONFIG_HOME: path.join(temporaryHome, ".config"),
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_TERMINAL_PROMPT: "0",
    GCM_INTERACTIVE: "Never",
    LANG: "C",
    LC_ALL: "C",
  };

  try {
    await runGit(["init", "--quiet", sourceRoot], gitEnvironment);
    await runGit(["-C", sourceRoot, "remote", "add", "origin", SOURCE_URL], gitEnvironment);
    await runGit(["-C", sourceRoot, "fetch", "--quiet", "--depth", "1", "--no-tags", "origin", SOURCE_REVISION], gitEnvironment);
    await runGit(["-C", sourceRoot, "checkout", "--quiet", "--detach", "FETCH_HEAD"], gitEnvironment);
    const checkedOutRevision = (
      await runGit(["-C", sourceRoot, "rev-parse", "HEAD"], gitEnvironment)
    ).trim();
    if (checkedOutRevision !== SOURCE_REVISION) {
      throw new Error(`checked out revision ${checkedOutRevision}, expected ${SOURCE_REVISION}`);
    }
    await installSkills(await fs.realpath(sourceRoot), homeRoot);
  } finally {
    await fs.rm(temporaryRoot, { recursive: true, force: true });
  }

  process.stdout.write(
    `Installed pstack ${PSTACK_VERSION} at ${SOURCE_REVISION}; restart OpenCode to discover the new skills.\n`,
  );
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`setup-pstack: ${message}\n`);
  process.exitCode = 1;
});
