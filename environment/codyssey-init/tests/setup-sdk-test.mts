import assert from "node:assert/strict";
import { copyFile, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";
import type { SetupOutput } from "../sdk/setup.mts";

test("SDK operations can run together and receive independent choices", async () => {
  const root = await mkdtemp(join(tmpdir(), "codyssey-sdk-test."));
  try {
    await mkdir(join(root, "sdk"));
    await mkdir(join(root, "scripts"));
    await copyFile(new URL("../sdk/setup.mts", import.meta.url), join(root, "sdk/setup.mts"));
    await writeFile(join(root, "macos-setup.sh"), [
      'printf "%s %s %s\\n" "$*" "$CODYSSEY_DOCK_SETUP" "$CODYSSEY_DOCK_LAUNCHER"',
      'touch input-started',
      'while [ ! -f preparation-started ]; do sleep 0.01; done',
    ].join("\n"));
    await writeFile(join(root, "scripts/prepare-startup.sh"), [
      '[ -z "$TS_AUTHKEY" ] && [ -d "$(dirname "$1")" ] || exit 9',
      'touch preparation-started',
      'while [ ! -f input-started ]; do sleep 0.01; done',
      'printf "prepared\\n"',
    ].join("\n"));
    await writeFile(join(root, "next-script.zsh"), [
      '[[ $1 == --prepared && $CODYSSEY_OPEN_BROWSER == 0 && $CODYSSEY_INTERACTIVE_SHELL == 0 ]] || exit 7',
      '[[ -z $TS_AUTHKEY && -n ${TS_AUTHKEY+x} ]] || exit 8',
      '[[ $2 == --result ]] || exit 9',
      'printf "%s\\n" needs-login http://localhost:18081 https://login.tailscale.com/a/synthetic >"$3"',
      'printf "login pending\\n"',
    ].join("\n"));

    const sdkURL = pathToFileURL(join(root, "sdk/setup.mts"));
    const sdk: typeof import("../sdk/setup.mts") = await import(sdkURL.href);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(new Error("SDK operations did not overlap")), 5000);
    const inputOutput: string[] = [];
    const prepOutput: string[] = [];
    const capture = (lines: string[]) => ({ text }: SetupOutput) => { lines.push(text); };
    try {
      const [input, prep] = await Promise.all([
        sdk.configureMacOSPreferences({ scope: "input" }, { signal: controller.signal, onOutput: capture(inputOutput) }),
        sdk.prepareTailnet({ signal: controller.signal, onOutput: capture(prepOutput) }),
      ]);
      assert.deepEqual(input, { exitCode: 0, signal: null });
      assert.deepEqual(prep, { exitCode: 0, signal: null });
      assert.equal(inputOutput.join(""), "--input-only 0 0\n");
      assert.equal(prepOutput.join(""), "prepared\n");
    } finally {
      clearTimeout(timeout);
    }

    const startOutput: string[] = [];
    const result = await sdk.startTailnet({ mode: "browser" }, { onOutput: capture(startOutput) });
    assert.deepEqual(result, {
      exitCode: 0, signal: null, state: "needs-login",
      gostUrl: "http://localhost:18081", loginUrl: "https://login.tailscale.com/a/synthetic",
    });
    assert.equal(startOutput.join(""), "login pending\n");
    await assert.rejects(sdk.startTailnet({ mode: "key", key: "invalid" }), /Invalid Tailscale auth key/);

    await writeFile(join(root, "macos-setup.sh"), 'printf "running\\n"; sleep 30');
    const cancellation = new AbortController();
    await assert.rejects(sdk.configureMacOSPreferences({ scope: "input" }, {
      signal: cancellation.signal,
      onOutput: () => cancellation.abort(new Error("operator canceled")),
    }), /operator canceled/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
