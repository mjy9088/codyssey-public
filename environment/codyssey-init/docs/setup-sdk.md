# TypeScript setup SDK

The SDK is available in the [environment source directory](../).

Import `sdk/setup.mts` from this project with Node.js 22.18 or newer and native TypeScript
support. The bootstrap uses a working Node on `PATH` or installs the pinned Node 24.11.1 through
mise when needed. The SDK calls the same platform scripts as the existing bootstrap. Callers
provide choices as values. The macOS Gureum approval dialog still belongs to the logged-in desktop.

```typescript
import { configureMacOSPreferences, prepareTailnet, startTailnet } from "./sdk/setup.mts";

const [keyboard, preparation] = await Promise.all([
  configureMacOSPreferences({ scope: "input" }),
  prepareTailnet(),
]);
if (keyboard.exitCode !== 0) console.error("Input setup failed.");
if (preparation.exitCode === 0) {
  const services = await startTailnet({ mode: "browser" });
  if (services.state === "needs-login") {
    // Present services.loginUrl to the operator through the frontend.
  }
}
```

Use `configureMacOSPreferences` for input, Dock, shortcuts, or combined settings. It accepts
explicit choices for Dock cleanup and the launcher. `installLauncher`, `installIterm2`,
`configureIterm2`, and `configureShell` are independent entry points. Run Tailnet preparation
and workstation operations concurrently when needed. Serialize operations that edit the same
preferences or the same Compose project, and run `startTailnet` only after preparation succeeds.
The Tailnet operations expect a running Docker engine with Compose and mise available on `PATH`.

Operations accept an `AbortSignal` and an optional `onOutput` callback. Output arrives as
stdout/stderr chunks. Treat login URLs as private. Operation results include the exit code and
termination signal. Tailnet startup also returns its readiness state and the applicable URLs.
Browser login, an existing `.env`, or an explicit key are separate authentication choices. An
explicit SDK key is passed to the child environment. The SDK uses neither an auth prompt nor a
browser launch, and does not write the key to a configuration file.
