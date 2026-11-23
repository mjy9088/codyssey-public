import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { constants, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

export type SetupOutput = { stream: "stdout" | "stderr"; text: string };
export type OperationOptions = {
  signal?: AbortSignal;
  onOutput?: (output: SetupOutput) => void;
};
export type OperationResult = { exitCode: number; signal: NodeJS.Signals | null };
export type MacOSPreferences = {
  scope: "all" | "input" | "dock" | "shortcuts";
  cleanDock?: boolean;
  installDockLauncher?: boolean;
};
export type TailnetAuthentication =
  | { mode: "browser" }
  | { mode: "saved" }
  | { mode: "key"; key: string };
export type TailnetStartResult = OperationResult & (
  | { state: "running"; tunnelUrl: string }
  | { state: "needs-login"; tunnelUrl: string; loginUrl: string }
  | { state: "failed" }
);

const root = fileURLToPath(new URL("../", import.meta.url));
type RunnerOptions = OperationOptions & { terminal?: boolean };

function run(
  executable: string,
  args: string[],
  environment: NodeJS.ProcessEnv,
  options: RunnerOptions,
): Promise<OperationResult> {
  options.signal?.throwIfAborted();
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      cwd: root,
      env: environment,
      detached: !options.terminal,
      stdio: options.terminal ? "inherit" : ["ignore", "pipe", "pipe"],
    });
    const cancel = () => {
      if (child.pid === undefined) return;
      if (options.terminal) {
        child.kill("SIGTERM");
      } else {
        try { process.kill(-child.pid, "SIGTERM"); }
        catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;
        }
      }
    };
    options.signal?.addEventListener("abort", cancel, { once: true });
    if (options.signal?.aborted) cancel();
    let outputFailed = false;
    let outputError: unknown;
    for (const stream of ["stdout", "stderr"] as const) {
      child[stream]?.setEncoding("utf8").on("data", (text: string) => {
        try {
          options.onOutput?.({ stream, text });
        } catch (error) {
          outputFailed = true;
          outputError = error;
          cancel();
        }
      });
    }
    child.once("error", reject);
    child.once("close", (code, signal) => {
      options.signal?.removeEventListener("abort", cancel);
      if (options.signal?.aborted) reject(options.signal.reason);
      else if (outputFailed) reject(outputError);
      else resolve({ exitCode: code ?? (signal ? 128 + constants.signals[signal] : 1), signal });
    });
  });
}

function shell(path: string, args: string[], env: NodeJS.ProcessEnv, options: RunnerOptions) {
  return run("bash", [join(root, path), ...args], env, options);
}

const preferenceModes = {
  all: [],
  input: ["--input-only"],
  dock: ["--desktop-only"],
  shortcuts: ["--shortcuts-only"],
} as const;

export function configureMacOSPreferences(preferences: MacOSPreferences, options: OperationOptions = {}) {
  const env = {
    ...process.env,
    CODYSSEY_INPUT_SWITCH: "control-space",
    CODYSSEY_DOCK_SETUP: preferences.cleanDock ? "1" : "0",
    CODYSSEY_DOCK_LAUNCHER: preferences.installDockLauncher ? "1" : "0",
  };
  return shell("macos-setup.sh", [...preferenceModes[preferences.scope]], env, options);
}

export function installIterm2(options: OperationOptions = {}) {
  return shell("scripts/install-iterm2.sh", [], process.env, options);
}

export function configureIterm2(options: OperationOptions = {}) {
  return shell("scripts/configure-iterm2.sh", [], process.env, options);
}

export function configureShell(options: OperationOptions = {}) {
  return shell("scripts/configure-shell.sh", [], process.env, options);
}

export function installLauncher(options: OperationOptions = {}) {
  return shell("scripts/install-managed-j.sh", [], process.env, options);
}

export async function prepareTailnet(options: OperationOptions = {}) {
  options.signal?.throwIfAborted();
  const directory = await mkdtemp(join(tmpdir(), "codyssey-sdk-preparation."));
  try {
    return await prepareWorker(join(directory, "result"), join(directory, "ready"), options);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

export async function startTailnet(
  authentication: TailnetAuthentication,
  options: OperationOptions = {},
): Promise<TailnetStartResult> {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    CODYSSEY_OPEN_BROWSER: "0",
    CODYSSEY_INTERACTIVE_SHELL: "0",
    CODYSSEY_WORKSTATION_INCOMPLETE: "0",
  };
  delete env.TS_AUTHKEY;
  if (authentication.mode === "browser") env.TS_AUTHKEY = "";
  if (authentication.mode === "key") {
    if (!/^tskey-auth-[A-Za-z0-9_-]+$/.test(authentication.key)) {
      throw new TypeError("Invalid Tailscale auth key.");
    }
    env.TS_AUTHKEY = authentication.key;
  }
  options.signal?.throwIfAborted();
  const directory = await mkdtemp(join(tmpdir(), "codyssey-sdk-tailnet."));
  const resultPath = join(directory, "result");
  try {
    await writeFile(resultPath, "", { mode: 0o600 });
    const result = await startPrepared(env, options, resultPath);
    if (result.exitCode !== 0) return { ...result, state: "failed" };
    const [state, tunnelUrl, loginUrl] = (await readFile(resultPath, "utf8")).split("\n");
    if (state === "running" && tunnelUrl) return { ...result, state, tunnelUrl };
    if (state === "needs-login" && tunnelUrl && loginUrl?.startsWith("https://login.tailscale.com/")) {
      return { ...result, state, tunnelUrl, loginUrl };
    }
    throw new Error("Tailnet startup did not return a valid readiness result.");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

// The shell frontend owns prompts and the preparation worker's ready/result files.
/** @internal Legacy CLI worker entry point. */
export function prepareWorker(result: string, ready: string, options: RunnerOptions) {
  return shell("scripts/prepare-startup.sh", [result, ready], { ...process.env, TS_AUTHKEY: "" }, options);
}

/** @internal Legacy CLI continuation with inherited authentication and terminal. */
export function startPrepared(env: NodeJS.ProcessEnv, options: RunnerOptions, resultPath?: string) {
  const args = options.terminal ? ["-i"] : [];
  args.push(join(root, "next-script.zsh"), "--prepared");
  if (resultPath !== undefined) args.push("--result", resultPath);
  return run("zsh", args, env, options);
}

/** @internal Legacy CLI preference prompts and environment overrides. */
export function configureMacOSFromTerminal(mode: string[], options: RunnerOptions) {
  return shell("macos-setup.sh", mode, process.env, options);
}
