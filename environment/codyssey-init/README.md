# Codyssey macOS tailnet bootstrap

This is a shared macOS workstation bootstrap for course participants. It installs or reuses
iTerm2 as a basic application. Personal Tailnet services and workstation preferences are
separate choices, all with **No as the default**. Pressing Enter or running without a terminal
skips Tailscale/GOST, the `j` command and Dock launcher, and macOS keyboard/text/Dock settings.
Declining an option preserves an existing installation; it does not uninstall apps, remove
commands, stop previously running services, or overwrite user configuration.

The bootstrap does not install Docker, authenticate to Tailscale by itself, or prove that a remote
tailnet is reachable. A selected Tailnet or `j` setup can install a pinned, checksum-verified
`mise` binary when it is missing.

## Optional features

Run the same root `sh init.sh` command again whenever you want to choose features.
If you started with the remote one-line command, repeat that same command. The questions
are asked on every interactive run, even when an earlier run created `.env`, installed `j`,
or started services. No separate `tailnet.sh` command is needed to configure or retry setup.
Declining this time preserves earlier work; selecting Yes reuses or retries that feature.

Interactive prompts use `[y/N]`: only `y`, `Y`, `yes`, or `YES` opts in. These choices are
independent; a Tailnet failure does not suppress a separately selected `j` or macOS setup.
For unattended runs, set an option explicitly to `1` to enable it or `0` to disable it:

| Variable | Choice | Default |
| --- | --- | --- |
| `CODYSSEY_TAILNET_SETUP` | Prepare Docker, build/start Tailscale and GOST, configure authentication and open the Tailnet browser | `0` |
| `CODYSSEY_INSTALL_J` | Install the managed `~/.local/bin/j` command and macOS Dock launcher | `0` |
| `CODYSSEY_MACOS_SETUP` | Apply personal keyboard, text, and optional Dock preferences | `0` |
| `CODYSSEY_DOCK_SETUP` | Clean Dock pins/stacks within selected macOS setup | `0` |

For example, from the repository root, explicitly select only the Tailnet services:

```sh
CODYSSEY_TAILNET_SETUP=1 CODYSSEY_INSTALL_J=0 CODYSSEY_MACOS_SETUP=0 sh init.sh
```

For all personal features in an unattended run (including destructive Dock cleanup):

```sh
CODYSSEY_TAILNET_SETUP=1 CODYSSEY_INSTALL_J=1 CODYSSEY_MACOS_SETUP=1 \
  CODYSSEY_DOCK_SETUP=1 sh init.sh
```

`TS_AUTHKEY` alone does not opt into Tailnet setup. Without `CODYSSEY_TAILNET_SETUP=1`
(or an affirmative prompt response), no Docker probe/start, authentication prompt, `.env`
creation, service creation, or Tailnet browser setup occurs. Shell activation blocks are only
added for selected Tailnet or `j` tools. Choosing `j` alone adds its launcher without changing
keyboard, input methods, text settings, or existing Dock pins. Using that launcher later
requires explicitly configuring a working Tailnet environment.

## Availability and trusted source

The repository-root entry point delegates to this existing Bash bootstrap from a
reviewed local checkout (run from the repository root, not this environment directory):

```sh
sh init.sh
```

For the shortest remote command:

```sh
curl -fsSL https://raw.githubusercontent.com/mjy9088/codyssey-public/main/init.sh | sh
```

The remote command downloads the latest public `main` branch. It buffers the bootstrap before
execution. Revision and mirror overrides are not supported; run `sh init.sh` from a reviewed local
checkout when a fixed revision is needed. `sh init.sh --help` works without network access.
The repository-root `init.sh` is the only supported public bootstrap entry point.
The old `install.sh` download wrapper has been removed. Implementation and maintenance
helpers such as `macos-setup.sh` and `enable-korean.swift` belong only in this directory,
not as independent copies at the monorepo root. Unless a command explicitly says to run
from the repository root, run this document's maintenance commands from
`environment/codyssey-init/`; all public `sh init.sh` bootstrap examples refer to the root wrapper.

Remote mode stages the complete reusable runtime, including `init.sh`, `verify-macos-setup.py`, and
runtime libraries, before copying anything into
`${CODYSSEY_INIT_DIR:-$HOME/.local/share/codyssey-init}`. It refuses to overwrite a different
installer file during a full preflight. Failed downloads leave the target untouched and remove their
staging directory. Existing `.env` and `gost/gost.yaml` files are preserved. A local checkout runs in
place and rejects a different `CODYSSEY_INIT_DIR`, avoiding a partial or ambiguous copy.

## Prerequisites

- for selected Tailnet setup: macOS with OrbStack installed in `/Applications` or `~/Applications`, or another running Docker Engine exposing Compose
- `zsh`, `curl`, and ordinary terminal access
- for selected Tailnet setup: access to `/dev/net/tun` and permission for Docker to grant `NET_ADMIN` and `NET_RAW`
- for selected Tailnet setup: optionally, a Tailscale auth key or permission to complete browser login

The script reuses `mise` from the current path or `$HOME/.local/bin`. When it is missing, macOS arm64
and x86_64 use the official `mise` v2026.10.5 release binary with a repository-pinned SHA-256 value.
No mutable shell installer is executed. Automatic installation requires `curl`, `shasum`, `cut`,
`install`, and `mktemp`; unsupported systems and architectures fail clearly. The repository-owned
`mise.toml` pins `just` to `1.43.0`. Startup preparation runs with an explicitly empty exported
`TS_AUTHKEY`: it trusts the local config, installs `just@1.43.0`, builds the Tailscale image, and
pulls the pinned GOST images. `next-script.zsh` refreshes the shell environment with
`mise env -s zsh` before Compose starts.
Portable-browser preparation is deliberately not part of this worker: `--prepare` updates the
dedicated profile and extension copy, so it stays in the foreground browser path rather than racing
another profile operation.

After Tailnet opt-in, `init.sh` reuses a working Docker engine. Otherwise, on macOS with no explicit `DOCKER_HOST` or
`DOCKER_CONTEXT`, it starts the installed OrbStack through its bundled `orb start` command, bypassing
the first-run Next button. It adds the bundled Docker tools as a fallback on PATH, registers missing
Compose and Buildx plugins under `${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins`, and waits up to 60
seconds for Docker readiness. Existing plugin files and explicit Docker targets are preserved.
The fallback tools path is also added to `.zshrc` for later terminals. OrbStack itself must already
be installed; the bootstrap does not download it. The CLI is documented in
[OrbStack commands](https://docs.orbstack.dev/machines/commands).

With Tailnet selected, `init.sh` then starts preparation in the background before any optional `j` or Dock prompt and keeps
ownership of that worker through Tailscale input and preparation completion. It prints concise start,
wait, and completion status while preparation output stays in a private temporary log, so build output
cannot interleave with prompts. The log is removed after success, failure, or cancellation. Only after
successful preparation does `init.sh` launch `next-script.zsh --prepared`; no live worker crosses the
Bash-to-zsh boundary. Running `next-script.zsh` directly performs the same preparation under zsh's
ownership. Secret input is read directly and silently from `/dev/tty`, and the exact saved terminal
state is restored.

When standard output is a terminal and a controlling terminal is available, `init.sh` offers to
install `~/.local/bin/j`, reading and writing the prompt through `/dev/tty`. This also works when the
bootstrap script itself arrives through piped standard input. Enter declines (the `[y/N]` default). An explicit `y`, `Y`, `yes`, or `YES`
installs a directly executable, mode-`0700` POSIX wrapper that changes to the resolved `codyssey-init`
directory and runs `just` with the original arguments and exit status. Later accepted runs update that
target atomically. The wrapper starts with `#!/bin/sh` followed by its ownership marker; the bootstrap
also recognizes and migrates the earlier marker-first layout. Another existing `j` is preserved with
a warning. Headless and unreadable-terminal runs skip the command unless `CODYSSEY_INSTALL_J=1` is supplied.
Declined runs do not create or change the command or Dock launcher.

## TypeScript setup SDK

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

## Authentication and startup

This section applies only after Tailnet setup is explicitly selected.

An exported `TS_AUTHKEY`, including an intentionally empty value, takes precedence and is passed to
Compose without creating or changing `.env`. Otherwise an interactive run asks for either:

- a Tailscale auth key;
- a pasted Tailscale install/up command containing an auth key; or
- a blank line to use browser login.

The prompt also appears when `.env` already exists, allowing an expired or consumed key to be
replaced for this run. The choice is exported in memory and the saved file remains unchanged.
Unattended runs preserve and reuse existing `.env` configuration; reusable keys are appropriate
for unattended ephemeral restarts. If no file exists, the initial choice is published atomically
as a mode-`0600` `.env` file. An ephemeral restart needs browser login or a valid new/reusable key;
one-use keys cannot authenticate a second new identity.

Pasted text is never executed. A complete `tskey-auth-` token using the documented alphanumeric,
underscore, and hyphen alphabet is extracted; a malformed token is rejected rather than partially
matched. Terminal echo is restored from the exact saved `stty -g` state on success, failure, and
signals. If no controlling terminal exists, the script safely creates an empty mode-`0600` `.env` and
continues to the browser-login path without attempting to read or truncate `/dev/tty`.

Authentication and input-independent preparation may overlap, but services do not start until both
are complete. After the prepared build and pulls succeed, Compose starts without rebuilding:

```sh
docker compose up -d --no-build
```

Preparation failure stops startup before any service is created. Caller-supplied legacy preparation
variables are ignored. Signals terminate only worker-owned process groups, allow a bounded grace
period, then kill and reap stubborn descendants before removing the private log. The bootstrap then
waits for all three containers and a
Tailscale `Running` or `NeedsLogin` state. A
`NeedsLogin` state is not reported as a connected tailnet: the script extracts and prints the actual
`https://login.tailscale.com/...` authentication URL from Tailscale's output. The entry point keeps the daemon alive throughout browser
authentication, avoiding the upstream container wrapper's 60-second startup timeout. It reads the current URL from status, with the latest logged URL as a fallback, and waits up to 60 seconds
for that URL because `NeedsLogin` can appear before the URL is available, then fails with a command
to inspect the logs if no URL is available:

```sh
docker compose logs tailscale
```

The login URL opens automatically in the system default browser, without waiting for the portable
browser download or profile setup and without using its unauthenticated Tailnet proxy.
It then waits for the local GOST UI and opens Chrome when available, falling back to the default
portable Tailnet browser by default (or the installed browser with `CODYSSEY_BROWSER=system`). Interactive runs finish in zsh with `mise` and `just` available. The URL is:

<http://localhost:18081/?api=http%3A%2F%2Flocalhost%3A18080>

Set `CODYSSEY_OPEN_BROWSER=0` for unattended or headless runs. Both URLs are still printed, but no
browser is launched. VM verification uses this mode to avoid first-launch browser dialogs blocking
the bootstrap.

macOS preference failures print a warning and a command to retry them separately.
They do not prevent container startup or browser setup. Docker, tool installation, and service readiness failures return a nonzero status.
Independent workstation settings are attempted even when Docker or tool preparation fails;
steps that require those prerequisites are skipped. Tailscale readiness and GOST UI readiness
are checked independently, so one failing service does not suppress the other result.

## Repeated runs, diagnostics, and environment differences

Run `sh init.sh` again after correcting a failed prerequisite. Completed work is reused:
managed `j` is replaced atomically, shell activation blocks are written atomically and added once, existing `.env`
and GOST configuration are preserved. A running Tailscale process keeps its session; a restart
or recreation deliberately starts a new ephemeral identity.
iTerm2 is part of the default macOS application setup. A valid existing system or per-user
iTerm2 is reused; otherwise the checksum-pinned universal iTerm2 3.7.7 ZIP is installed
under `~/Applications` without sudo or launching it. The complete bundle is staged before
publication, so failed installs can be retried. See the [checksum source](https://formulae.brew.sh/api/cask/iterm2.json).
The default profile sets **Left Option = Esc+** and enables **Apps can change how keys are reported**,
using user preferences without Accessibility or Automation permission. Other profiles and
Right Option remain unchanged. Existing preferences are backed up privately under
`~/Library/Application Support/codyssey-init/iterm2-backups`. Quit a running iTerm2 and rerun
the same init command from Terminal to apply the settings; custom preference-folder configurations are
preserved and reported for manual setup. See [iTerm2 keyboard settings](https://iterm2.com/documentation-preferences-profiles-keys.html).
OrbStack windows are left under the user's control; the bootstrap does not hide them.

Each runtime invocation prints its private diagnostic log path under
`~/Library/Logs/codyssey-init/run.*` (directory mode `0700`, files `0600`). Logs survive
success, failure, and cancellation. Attach that file to a problem report, together with the
command you ran, the repository revision (`git rev-parse HEAD` for a checkout), and the
visible error. The shareable log records UTC timestamps, macOS/architecture, stage outcomes,
and exit codes. It deliberately excludes command output, environment dumps, auth input,
Tailscale login URLs, and container logs. Detailed tool diagnostics still appear in the
terminal on failure. Review any extra terminal output before sharing it. When runtime setup
exits with an error in a terminal, the prompt shows the shareable log path and the
upload destination. Press Enter or type `y` to send it,
or type `n` to decline. Unattended runs and cancellations skip the prompt. Delete old log
files manually when no longer needed. If logging is unavailable, a warning is printed and
setup continues. Remote download/preflight failures occur before the runtime log exists,
so include their terminal error separately.

A transient browser-control socket timeout is retried once after its setup browser closes.
Repeated timeouts and policy/ownership errors are reported; the latter are never retried.

A successful command does not guarantee every macOS setting took effect. OS versions,
hardware, app locations/versions, Docker backends, existing user preferences, permissions,
input-method approvals, and managed-device policy can produce different results. Preferences
may be partially applied; inspect the warnings and verify the actual Dock, shortcuts, Korean
input, and browser behavior in your environment. Retry the relevant command below after fixing
the cause. OrbStack startup failure does not prevent a separately selected Dock launcher from being attempted.
Declining Dock cleanup adds the launcher only when `j` was explicitly selected. The launcher requires a working container when used.
Repeated runs cannot bypass system approval or make an incompatible Docker backend compatible.
A remote install refuses differing runtime files instead of overwriting them; for an upgrade,
use a fresh reviewed checkout or preserve your configuration and choose a fresh install directory.

### Comparing environments

Record the actual macOS build and architecture (`sw_vers` and `uname -m`), Swift version, app
versions and install locations, and Docker Engine/Compose versions. To reproduce an incident,
match the affected environment when available. An Apple Silicon guest on a different OS build
provides coverage for that guest. Bootstrap download pins identify the artifacts used when a
component needs installing.

| Component | Example from an Intel reference workstation |
| --- | --- |
| macOS and CPU | 15.7.5, x86_64 |
| OrbStack, Docker CLI, Compose | 2.0.5, 28.5.2, 2.40.3 |
| mise and just | 2026.10.5 (macos-x64), 1.43.0 |
| Installed Chrome and portable Chrome | 146.0.7680.165, 155.0.8059.39 (mac-x64) |
| Gureum | 1.13.2, universal bundle under `/Library/Input Methods` |
| System Python | 3.9.6. Use the container checks when Python 3.10+ is unavailable. |


## Container privilege and mount boundary

The Tailscale service intentionally uses kernel networking (`TS_USERSPACE=false`), host networking,
`/dev/net/tun`, and the `NET_ADMIN` and `NET_RAW` capabilities. It also mounts `${HOME}` read/write at
`/host` so the explicitly requested environment shell can work with the macOS user's files. This is
a broad trust boundary: anyone with a shell in that container can modify the mounted home directory.
Run only the reviewed image and scripts, and do not enable this Compose project where those privileges
or that mount are unacceptable.

On OrbStack, host networking refers to its Linux VM, not the macOS host network. The SOCKS5 listener
at `127.0.0.1:1055` and the GOST chain remain available alongside kernel networking; The entry point configures that listener alongside the TUN device. See the
[Tailscale Docker parameters](https://tailscale.com/docs/features/containers/docker/docker-params).

Tailscale runs with `tailscaled --state=mem:` and a private tmpfs at `/var/run/tailscale`.
Both browser and auth-key logins create ephemeral nodes; no identity volume is mounted or restored.
Graceful daemon shutdown logs out the ephemeral node, removing it from Machines. After a crash,
forced kill, network loss, or abrupt workstation reset, removal waits for the coordination server's
inactivity timeout. Running nodes still appear in Machines with the ephemeral badge; this prevents
abandoned permanent entries, rather than hiding active devices. See the
[official ephemeral-node documentation](https://tailscale.com/docs/features/ephemeral-nodes) and
[shutdown behavior](https://tailscale.com/blog/ephemeral-logout).

Repeating init while the same container is running reuses that live session. Restarting, stopping
and starting, or recreating it loses the identity and requires authentication again.
The GOST API listens only on
`127.0.0.1:18080`, and the UI is published only on `127.0.0.1:18081`. No forwarding service is enabled
by default. Add services with loopback listener addresses unless deliberate external exposure is
required.

## Tailnet shell and `just`

Use the same init command again to select or retry Tailnet setup. If you also opted into
`j`, open the configured terminal from its Dock launcher or run `j`. From the installation
directory, `just` (or `just bash`) opens Bash in the Tailscale container, and `just zellij`
opens the multiplexer. Those are optional shortcuts; they are not additional setup entry points.

The internal terminal helper preserves arguments and command exit status, retains a TTY for
interactive use, and uses Compose's non-TTY mode for redirected calls. Bash and zellij probe
for their required tools and rebuild an older image only when those tools are missing.
Rebuilding the terminal image recreates the ephemeral node and may require login again.

The image includes checksum-verified mise 2026.10.5 and zellij 0.45.1 installed through mise.
Interactive Bash activates mise automatically, and its shims are also available to direct commands.
Use `just zellij` to start the terminal multiplexer; plain `just` continues to open Bash. Global
container tools live under `/opt/mise` with configuration in `/etc/mise`, separate from `/host`.

Once connected, the entry point updates only the container's Docker-mounted `/etc/resolv.conf`
in place: it points to Tailscale's `100.100.100.100` resolver and adds the current tailnet's MagicDNS
search domain. Thus both `ssh peer-name` and fully qualified tailnet names work in this shell.
The original Docker resolver remains in use before login and is restored after `tailscale down`.
Tailnet DNS forwarding remains enabled, and host-network mode does not change the macOS resolver.

## Portable Tailnet browser

On macOS the bootstrap now opens a portable **Chrome for Testing 155.0.8059.39** with the Tailnet
extension loaded automatically. No browser installation, Web Store visit, Developer mode toggle, or Load unpacked step is
needed. The launcher chooses `mac-x64` on x86_64 and `mac-arm64` on Apple Silicon, downloads from
Google's versioned archive, verifies its pinned SHA-256, and extracts into
`~/Library/Caches/codyssey-init/`. It reuses the browser on later runs. Failed downloads, checksums,
or extraction leave no installed browser and remove staging files.

```sh
just browser
# Or open a particular website:
bash scripts/tailnet-browser.sh https://server.example.ts.net
# Download and prepare without opening a window:
bash scripts/tailnet-browser.sh --prepare
```

On the first launch and whenever the bundled extension changes, the launcher configures the dedicated
profile automatically: it enables Chrome Developer mode, reloads the unpacked extension, and verifies
that its worker responds. It uses Python 3 from Xcode Command Line Tools and a temporary DevTools
endpoint bound to loopback. Only the dedicated profile is restarted, with tabs restored. The setup
browser and debugging endpoint close before normal Chrome starts. Managed policy or another
extension controlling the proxy produces an error; no macOS permissions or administrator rights
are granted. An unchanged, configured profile opens without this extra restart.

The browser uses its own profile and extension copy under
`~/Library/Application Support/codyssey-init/`. All websites routing enables automatically on the first
launch; later launches preserve the user's routing choice. Browser web connections use the local
SOCKS5 listener, with DNS resolution and routing in the container. Custom domain names and advertised
subnet destinations work without a browser allowlist. Localhost, loopback, and `.local` stay direct.
Its popup can select the narrower Tailnet-only mode or disable routing. The 1.1.0 upgrade migrates
an enabled 1.0.0 Tailnet-only configuration to All websites once; disabled routing stays disabled. It needs only the `proxy` permission, and does not
authenticate Tailscale or provide a system-wide VPN. Keep the Tailscale container running and logged in.

The version and archive integrity pins live in `scripts/browser-version.sh`. The browser does not
auto-update; update those pins deliberately to adopt another release. Synthetic tests cover both architecture selections. The disposable browser verifier exercises the
real executable and fresh profile on the guest architecture. The launcher can override its private locations with
`CODYSSEY_BROWSER_CACHE_DIR` and `CODYSSEY_BROWSER_SUPPORT_DIR`.

Additional local unpacked extensions can be registered in
`~/Library/Application Support/codyssey-init/unpacked-extension-paths`, one canonical absolute
directory per line. Each directory must contain a regular `manifest.json`. The launcher preserves
registration order and loads each unique valid directory after the built-in Tailnet extension.
The registry itself must be a readable regular file. Relative, stale, non-canonical,
comma-containing, empty, unreadable, and duplicate entries, failed path canonicalization, and
non-regular registry objects are reported and ignored; they never prevent the built-in extension or
browser from launching. Override the parent directory with `CODYSSEY_BROWSER_SUPPORT_DIR` when using
a private test location.

Use `CODYSSEY_BROWSER=system` to keep the installed-browser behavior. `CODYSSEY_OPEN_BROWSER=0`
skips browser downloads and launches during bootstrap. To install the extension into ordinary Chrome,
run `just chrome-extension`, enable Developer mode, click Load unpacked, and select the printed
`chrome-extension` directory. That ordinary installation starts with routing off.

Chrome for Testing supports [automatic extension loading](https://groups.google.com/a/chromium.org/g/chromium-extensions/c/1-g8EFx2BBY/m/S0ET5wPjCAAJ).
The browser archives come from [Google's Chrome for Testing project](https://github.com/GoogleChromeLabs/chrome-for-testing).
See [the extension documentation](chrome-extension/README.md) for routing details and troubleshooting.
The SOCKS proxy must be reachable from macOS at `127.0.0.1:1055`; this has been verified on the current
OrbStack installation. Other Docker engines may need port forwarding from their Linux VM.

## macOS preferences

When personal macOS preferences are selected, this environment disables text automation and configures **Gureum Hangul 2-set**
with **Control-Space for input switching and Command-Space for Spotlight**.
Control-Space is applied automatically without a switching-key prompt. Interactive setup
asks whether to clean up Dock pins and stacks. Enter declines and preserves existing pins
and stacks; explicit Yes keeps Terminal and Chrome. The j terminal launcher is added only
when `j` is separately selected.
Caps Lock remains unsupported. Independent preference groups continue after a failure and
report a nonzero summary status; the bootstrap continues container and browser setup.
To provide choices without prompting:

```sh
CODYSSEY_MACOS_SETUP=1 CODYSSEY_INPUT_SWITCH=control-space CODYSSEY_DOCK_SETUP=1 sh init.sh
```

`macos-setup.sh` refuses non-Darwin systems and never uses `sudo`. Before each independent preference
group, it creates a private per-run backup under
`~/Library/Application Support/codyssey-init/macos-backups/`. It then:

- disables macOS text automation;
- when Dock cleanup is accepted and both Terminal and Google Chrome exist, replaces Dock app pins with those two apps,
  hides recent items and removes folder stacks;
  the `Codyssey j.command` launcher is added only when explicitly selected, and declining cleanup preserves existing pins;
- preserves unrelated input sources while adding Gureum Hangul 2-set once;
- configures Control-Space and Control-Shift-Space for input switching, Command-Space for Spotlight,
  and Option-Command-Space for the Spotlight window, and disables Caps Lock switching; and
- restarts only the current user's Dock process when pins change.

`CODYSSEY_INPUT_SWITCH` accepts `control-space` or `caps-lock`; `CODYSSEY_DOCK_SETUP` accepts `0` or `1`.
Within selected macOS setup, Control-Space is used and existing Dock pins/stacks are preserved
unless `CODYSSEY_DOCK_SETUP=1` is supplied. The standalone maintenance script adds the launcher
only with `CODYSSEY_DOCK_LAUNCHER=1`; the root bootstrap sets that flag from the `j` choice.
`CODYSSEY_MACOS_SETUP=0` explicitly skips all macOS preferences during bootstrap.
`macos-setup.sh --input-only` changes input settings only; `--no-dock` also disables text automation.
`macos-setup.sh --shortcuts-only` applies and verifies the shortcut bindings without changing input sources.
The helper applies shortcuts even when System Settings is open, registers the live WindowServer
bindings directly, and verifies them in a fresh process as well as the writer.
No Screen Recording, Accessibility, administrator privileges, or logout are needed for shortcut setup.

macOS, CPU architecture, Swift/Command Line Tools, Docker, browsers, and apps can differ between
workstations and guests. Follow the environment comparison guidance above when investigating a failure.

When Gureum is absent, `scripts/install-gureum.sh` verifies the SHA-256 of the pinned 1.13.2
package and extracts it into `~/Library/Input Methods/Gureum.app` without sudo. An existing
bundle with the expected identifier and an executable is reused at its installed version. A
per-user bundle takes precedence over a system-wide bundle. Swift and the Xcode Command Line
Tools are required for Carbon registration and selection.

`enable-korean.swift` registers the installed app, enables its parent source
`org.youknowone.inputmethod.Korean` and Hangul mode `org.youknowone.inputmethod.Gureum.han2`, and attempts
to select Hangul. The legacy parent ID differs from the app's bundle ID,
`org.youknowone.inputmethod.Gureum`. After successful Gureum selection, it disables the Apple Korean
sources added by the earlier bootstrap. Choose Allow if macOS prompts. For up to 120 seconds the
helper services its run loop and attempts activation once the Hangul mode is enable-capable.
Gureum's QWERTY source uses `org.youknowone.inputmethod.Gureum.qwerty`. A stock ABC layout
uses `com.apple.keylayout.ABC`.
If the parent remains unavailable for 15 seconds or macOS rejects automatic selection with status
-50, the helper asks you to finish any pending Allow dialog. You can select Gureum Hangul 2-set
in the Input menu while the same run watches the current desktop input source. Add it under
**System Settings → Keyboard → Text Input → Edit** if needed. If it is listed but will not switch,
switch to a working source and try removing and re-adding just Gureum. If the installed input
method still does not appear in the picker, save your work and follow the
[Gureum installation instructions](https://github.com/gureum/gureum#수동-설치).

Carbon requires both the parent input source and the Hangul mode to be enabled before selecting
the mode. An accepted enable request can still be waiting for Allow. The helper re-reads live
state, treats a missing Carbon lookup as unavailable, and retries failed parent requests at
intervals. It leaves an accepted request pending to avoid reopening the approval dialog.

Even after both sources are enabled, Carbon may return -50. The helper shows the desktop recovery instructions once and retries at a slower
cadence for the rest of the activation window. This lets a pending approval finish or a manual
selection take effect. Completion requires Gureum to be the current input source. The desktop
typing check separately verifies that the active source actually composes Hangul.

Timeouts report observed TIS state and status codes while the remaining preference groups
continue. Keep a working Latin layout and Apple Korean available until Gureum is usable. To
retry in the same session after selecting Gureum:

```sh
bash macos-setup.sh --input-only
```

On registration failure or timeout, the helper writes a timestamped trace to stderr. It includes
changes in the live parent and Hangul mode flags, membership in the enabled-only list, the
current source, and Carbon return codes. Carbon does not identify the time of an Allow click
in this trace. Record that time separately to correlate it with the observed state changes.

For a stalled approval, run the following from the installed setup directory in a second
Terminal window on the affected desktop. Compile the helper before reproducing so Swift startup
does not delay the snapshot. Use the same probe after signing back in.

```sh
probe_dir=$(mktemp -d)
printf 'Probe and log directory: %s\n' "$probe_dir"
/usr/bin/swiftc enable-korean.swift -o "$probe_dir/gureum-probe"

# While Allow is visible
"$probe_dir/gureum-probe" --diagnose-gureum snapshot 2>&1 | tee "$probe_dir/before-allow.log"

# Immediately after clicking Allow
"$probe_dir/gureum-probe" --diagnose-gureum snapshot 2>&1 | tee "$probe_dir/after-allow.log"

# If the parent stays disabled after approval and setup exits
"$probe_dir/gureum-probe" --diagnose-gureum retry-parent 2>&1 | tee "$probe_dir/retry-parent.log"

# If it still stays disabled, log out and back in and set probe_dir to the printed path.
"$probe_dir/gureum-probe" --diagnose-gureum snapshot 2>&1 | tee "$probe_dir/after-login.log"
```

The snapshot reads live state without changing settings. The explicit retry can trigger an
approval prompt and samples state for five seconds after its single enable request. Neither
diagnostic selects an input source or removes Apple Korean.

Control-Space uses symbolic hotkey 60 with parameters `[65535, 49, 262144]`; Control-Shift-Space uses 61
with `[65535, 49, 393216]`. The old value `786432` was Control-Option-Space. After synchronizing preferences through CFPreferences,
the setup registers and enables the live bindings through SkyLight, waits for asynchronous application,
and verifies their values and enabled state. These private APIs target the reference macOS version;
missing symbols produce an error for this group while other setup groups continue.
Loaded shortcut registration does not prove physical key handling; test both Korean and English in a
focused text field. The setup does not automatically replace Gureum with Apple Korean when Caps Lock fails.
For a live check, type `gksrmf` in an editable document and verify that it composes `한글`.
Use Control-Space to switch in both directions and Command-Space to open Spotlight. If a focused
app switches input sources automatically, select Gureum again in that app before checking.
In Terminal, `/usr/bin/swift enable-korean.swift --current-source` prints the active source ID.

Every successful domain export is retained as `text.plist`, `dock.plist`,
`input-sources.plist`, or `hotkeys.plist` in the backup directory printed by the script. To restore a
particular run manually, set `backup` to that printed directory and import the snapshots that exist:

```sh
backup="$HOME/Library/Application Support/codyssey-init/macos-backups/run.REPLACE_ME"
defaults import NSGlobalDomain "$backup/text.plist"
defaults import com.apple.dock "$backup/dock.plist"
defaults import com.apple.HIToolbox "$backup/input-sources.plist"
defaults import com.apple.symbolichotkeys "$backup/hotkeys.plist"
killall -u "$USER" Dock
```

If a group has a `.missing` marker instead of a plist, that domain was confirmed absent before the
write. Restore that state with `defaults delete DOMAIN` rather than importing a file. Run only the
commands corresponding to files or markers in that backup directory. `NSGlobalDomain` is never
classified as absent.
Restoring a whole domain also reverts later changes in that domain. Restart affected applications;
input-source and shortcut changes may require logging out and back in.

### Dock launcher

Opting into `j` pins `Codyssey j.command` in the document area of the Dock. Clicking it opens
Terminal in this installation and runs `just`, with the user-local mise tools on PATH. It does not
require the optional global `j` wrapper. An unowned launcher is preserved. Declining Dock cleanup keeps existing pins, stacks and recent-app settings, and, when explicitly selected, adds only the j launcher without duplicates. Run
`CODYSSEY_DOCK_LAUNCHER=1 bash macos-setup.sh --desktop-only` to explicitly add the launcher.
Dock tiles use typed XML plist values: URL type 15 and file types are integers, not OpenStep
strings. This setup targets fresh installations; it does not migrate malformed tiles from older installs.

Notification dismissal is not automated: controlling Notification Center requires separate
Accessibility permission, which may already be granted to a VM's Guest Agent but is not assumed
for a classroom terminal. Clear existing notifications manually. To suppress future banners,
enable Do Not Disturb in Control Center or disable unwanted apps in System Settings > Notifications.
Those are per-user settings and require no administrator password.

Startup prints a single preparation message and the environment URL. Docker builds run privately;
service startup and terminal image upgrades are quiet on success. Failures include the last twelve
log lines and preserve the command's exit status. Temporary logs are removed after use.

### Destructive live preference verifier

`verify-macos-setup.py` is a deliberately destructive live test requiring Python 3.10 or newer. It
privately snapshots every preference domain before any write, requires an existing Latin keyboard
layout, removes symbolic-hotkey entries 60/61/64/65 from its baseline-derived fixture, clears Dock
pins, and enables all nine text-automation settings. The setup uses live TIS state to confirm Gureum
selection. The verifier applies the setup twice and verifies parsed plist values,
including exact Dock entries, typed hotkey parameters, and preservation of unrelated input sources
and shortcuts. It will not run without both Darwin and this exact opt-in:

```sh
CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 python3 verify-macos-setup.py
```

`--desktop-only` snapshots only Dock, applies the desktop setup twice, verifies the real launcher
with `--list`, and preserves keyboard/text preferences. The unattended VM uses this mode plus
independent live shortcut verification, so input-source approval cannot block its service tests.
The headless run reports the Gureum desktop check as pending. To complete it, open Terminal
inside the disposable VM desktop and run:

```sh
bash scripts/verify-macos-vm.sh --disposable --input-desktop
```

Choose Allow when prompted, then follow the typing prompts. The check requires Hangul composition,
Latin input after Control-Space, and Hangul composition after switching back. It checks the active
source in addition to the text typed into Terminal.

From `environment/codyssey-init`, run the same check from the host CLI against a stopped local
Tart base with a logged-in desktop, Guest Agent, and Swift. Install `uv` on the host and use the
Tart version selected by `mise -E vm`.

```sh
bash scripts/run-tart-input-check.sh BASE_VM
# On a base without prior Gureum approval, exercise the recovery guidance first.
bash scripts/run-tart-input-check.sh BASE_VM --expect-recovery
```

The runner clones the base, starts loopback VNC, waits for the guest, and prints the clone name
and private VNC log path. Choose Allow in the guest when prompted. With `--expect-recovery`,
leave Allow pending until the runner confirms that the recovery guidance appeared. Dismiss any
separate keystroke-monitoring request. The guest confirms each source change before the host
types the next sample. The runner stops its clone, deletes it on success, and retains it on
failure for diagnosis.
Add `--confirm-desktop` to wait for the operator to dismiss any extra dialog before typing.

Use a VNC viewer, or capture the screen and click from a second terminal using the name and log
printed by the runner. Use coordinates from the full-size PNG.

```sh
uv run --no-project --with vncdotool==1.4.2 python scripts/verify-tart-input.py VM_NAME "$tart_log" --capture "$(dirname "$tart_log")/screen.png"
uv run --no-project --with vncdotool==1.4.2 python scripts/verify-tart-input.py VM_NAME "$tart_log" --click X Y
```

The runner removes its temporary VNC log after shutdown. Keep screenshots private.
This mode does not verify notification dismissal or suppression.
The VM driver additionally runs `scripts/verify-dock-ui.swift` to require named, resolved Terminal,
Chrome and j items in the actual Dock UI. This read-only test requires the VM Guest Agent's existing
Accessibility authorization; it fails when unavailable rather than reporting UI success. Production
Dock setup does not use Accessibility or request this permission. Screenshots and a direct Terminal
launch are separate checks; a matching plist alone does not prove that Dock rendered an icon.

On success, the requested setup remains applied and the temporary verifier snapshot is removed. On
any failure or interruption, restoration is attempted for every captured domain before the original
error is rethrown. If any domain cannot be restored, the private snapshot is retained and its path is
printed for manual recovery. Do not run the verifier on a workstation whose live preferences may not
be temporarily changed. The VM procedure below exercises real preference changes and idempotence.
Failure restoration is covered by synthetic tests; authenticated tailnet login is outside its scope.

## Safe verification

The isolated check uses a digest-pinned Python 3.13.7 Alpine container, real Bash and zsh interpreters,
temporary synthetic homes, and fake Docker, `mise`, download, browser, Darwin, and macOS preference
commands. Its runtime has no network, writable source tree, host-home mount, capabilities, or service
exposure:

```sh
sh scripts/check.sh
# From the repository root, check the short entry point separately:
# sh scripts/check-init.sh
```

The root check separately builds an explicit allowlist containing only the root
entry point and its tests, then runs with no network, a read-only filesystem, a
temporary home, no added capabilities, and all capabilities dropped. It uses fake
download and Bash commands; it does not bootstrap the host.

The bounded test build context excludes private `.env`, user-edited GOST runtime configuration,
caches, and unrelated artifacts; it injects a synthetic GOST fixture instead. Bootstrap tests cover
successful, failed, repeated, and conflicting remote installs; preflight atomicity and
staging cleanup; verified missing-`mise` installation; exported-key and existing-`.env` precedence;
real-zsh execution; exact terminal-state restoration; browser-login URL handling; argument and exit
status preservation; Bash-only rebuild scope; preparation overlap across unanswered PTY prompts;
service-start gating; failure propagation; signal cleanup; and secret-free buffered output. The same
command also runs stateful macOS tests for
all preference groups, idempotence, private backups, confirmed absence versus export failure,
group-level rollback, interruption recovery, failed-rollback snapshot retention, app guards, and
current-user Dock restart behavior.
The isolated image also runs synthetic guest preparation and Docker-target boundary fixtures, plus
Compose ownership and Tart lifecycle tests. Guest preparation fixtures always run in this Linux
container and are skipped when invoked directly on Darwin. `--native-python` is macOS-only and prints
an explicit rejection on Linux; Linux hosts should use the default container command above.
Compose configuration and the Tailscale image build can also be checked without starting the
privileged service:

```sh
HOME=/tmp/codyssey-home TS_AUTHKEY= docker compose config
docker compose build tailscale
```

Keep runtime logs, browser profiles, preference backups, traces, and VM execution evidence in
private ignored storage. Review extra terminal and container output before sharing it.

These checks are local simulation and build/configuration evidence only. They do not activate TUN,
change host networking, authenticate Tailscale, or alter real macOS preferences.

## Service management

```sh
docker compose ps
docker compose logs -f
docker compose down
```

`docker compose down` gracefully stops services and logs out the ephemeral node.
`docker compose restart tailscale` starts a fresh identity and requires authentication again.
A one-use auth key may already be consumed; run the same init command and choose browser login
or a new/reusable key. There is no client identity volume to retain or remove.

For an isolated real authentication, restart/recreation, and MagicDNS test in a disposable Docker
environment, build the image and run from a source checkout:

```sh
docker compose build tailscale
python3 scripts/verify-tailnet-runtime.py --disposable
```

This uses a checksum-pinned Headscale 0.26.1 binary, an internal Docker network, and two local
Tailscale nodes with one-use lab auth keys. It verifies removal of old ephemeral nodes, fresh identities and required login after restart
and recreation, short and fully qualified MagicDNS names, resolver restoration, and mise/zellij commands.
The pinned Headscale 0.26.1 lab uses ephemeral one-use keys because that server classifies ephemerality
from the pre-auth key; hosted Tailscale additionally supports memory-state browser login.
It removes only its randomized lab containers, volumes, and network. This establishes local
control-plane behavior, not external tailnet ACLs, expiry policy, or remote peer reachability.

## Verification in a macOS VM outside the classroom

These scripts verify only this environment bootstrap. They use real Docker services and real macOS
preferences without an auth key. The normal bootstrap must remain in `NeedsLogin`; its authentication browser is disabled.
A separate browser check uses a fresh private profile and `about:blank`, and never completes external authentication. No coursework, remote tailnet access, or authenticated forwarding is
tested. The VM must be disposable: verification changes its user's `.zshrc`, Dock, keyboard settings,
and text preferences. The local lab authenticates synthetic nodes only to its own isolated Headscale server; it never logs into an external tailnet. Successful preference verification leaves the requested settings applied.

### Build a base with preinstalled applications

On Apple Silicon, install mise on the host. The host VM scripts use the opt-in
`mise.vm.toml` environment and install its pinned Tart 2.40.1 on macOS 14 or newer.
On Intel, prepare a Fusion Pro base as described under [Create a new macOS VM and run everything](#create-a-new-macos-vm-and-run-everything).
Ordinary `mise install`, the classroom bootstrap, and non-VM checks use `mise.toml`
(just only) and do not select Tart. There is no root-level Tart configuration.
See [mise config environments](https://mise.jdx.dev/configuration.html).

To use the same pin manually from this directory:

```sh
mise -E vm install tart
mise -E vm exec tart -- tart list
```

To reproduce the classroom's earlier startup stage, create a separate stopped base from an existing
reviewed Tart VM. The source must already have a logged-in desktop, Tart Guest Agent, Chrome,
Python 3 from Command Line Tools, and Swift. No Docker engine needs to be running:

```sh
bash scripts/create-preinstalled-macos-image.sh \
  --image reviewed-stopped-base --name codyssey-preinstalled
```

The builder clones the source and changes only that new VM. It installs checksum-pinned OrbStack
2.2.4 in `~/Applications` and ensures iTerm2 and Gureum are present. When absent, the builder
installs the pinned iTerm2 3.7.7 or Gureum 1.13.2 package. It completes this without launching onboarding,
activating input sources, sudo, or a Homebrew installation. The OrbStack archive pins come from the
[official Homebrew cask](https://github.com/Homebrew/homebrew-cask/blob/master/Casks/o/orbstack.rb).
The reference diagnostic used OrbStack 2.2.3 on Intel macOS 15.7.4; this newer pinned app and an ARM
Tart guest are not an exact hardware/version reproduction.

When cloning one of the earlier Colima verification VMs, the builder stops its dedicated test
profile, unlinks Homebrew's Docker CLI packages, and removes only the bootstrap-owned OrbStack PATH
block from `.zshrc`, keeping a private backup. Packages, disks, unrelated shell settings and commands
are preserved. An unexpected Docker command remaining on the login PATH causes failure rather than
being silently deleted. The original VM is never modified. Successful creation prints `READY`, stops
and retains the new base; it does not claim that the OrbStack engine has run.

Use the base for the complete pre-deployment check:

```sh
bash scripts/create-macos-vm.sh --image codyssey-preinstalled --preinstalled
```

This mode first inspects the real OrbStack/Gureum/Chrome/iTerm2 bundles, checks the Gureum executable, executes
bundled Docker/Compose/Buildx version queries, checks Swift, and confirms that Docker is absent from
the login PATH. It never starts OrbStack. The cold-start suite then exercises the production startup
helper and full `init.sh` against temporary synthetic homes and fake engine commands, covering missing
CLI/plugins, preserved plugins and Docker targets, startup failures, timeout, and preparation handoff.

After those checks, it prepares the dedicated QEMU-TCG Colima profile and runs the real Docker,
local DNS/ephemeral lifecycle, Dock/shortcuts, and fresh portable-browser verification. The original
preinstalled base stays stopped and unchanged. `brew install` may leave existing Docker packages
unlinked, so preparation explicitly links the Docker CLI when needed.
Provisioning and service cleanup suppress routine tool output; failures show bounded diagnostics.

For another existing disposable macOS VM, the equivalent stages are:

```sh
python3 scripts/check-preinstalled-apps.py
python3 tests/preinstalled-tools-test.py
bash scripts/prepare-macos-vm.sh --disposable
DOCKER_CONTEXT=colima-codyssey-verify bash scripts/verify-macos-vm.sh --disposable
```

**Acceptance boundary:** real OrbStack engine execution is not a requirement for these pre-deployment
checks. Docker workloads use an explicitly selected software-emulated Colima engine; this is a planned
verification backend, not a fallback after an OrbStack failure. The application identity/CLI checks
are real, while OrbStack startup commands are simulated. Gureum approval and physical Hangul/Latin
switching, actual Terminal/Dock clicks, OS-controlled notification permissions, and access to a real
authenticated tailnet remain manual classroom checks. No input approval is automated.

OrbStack itself needs nested virtualization inside a macOS VM, which current
[Tart support](https://tart.run/faq/) does not provide for macOS guests. Switching to UTM does not by
itself address that API constraint: its [macOS backend](https://docs.getutm.app/settings-apple/settings-apple/)
also uses Apple Virtualization, and its documented [nested support](https://docs.getutm.app/updates/v4.6/)
is for Linux guests. This does not block the pre-deployment checks described above.

### Fresh portable-browser verification

```sh
python3 scripts/verify-portable-browser.py --disposable
```

This real desktop check configures a fresh temporary Chrome profile and its unpacked extension,
checks that the temporary debugging endpoint is gone before normal launch, and verifies that an
unchanged second launch reuses the browser without repeating setup. It closes only the browser
process owned by that unique test profile, then removes the profile. Browser downloads remain cached.
It never opens the Tailscale login URL, authenticates, or touches an existing user browser profile.

### Manual smoke test in a disposable desktop session

Run the root `sh init.sh` with the options relevant to the incident. Verify Gureum composition
and shortcuts using the [macOS preference checks](#macos-preferences). In the final zsh,
check `mise` and `just`. If the test environment has an authorized Tailnet, check `just bash`,
`mise --version`, `zellij --version`, MagicDNS short names, and proxy toggling in `just browser`.
Rerun setup to verify reuse, then check that a graceful Tailnet container restart removes the
ephemeral identity and requires a fresh login.

### An existing disposable VM

With Docker already running, Python 3.10+, Chrome, a logged-in desktop user, and ordinary macOS
preference domains present, run inside the guest:

```sh
cd environment/codyssey-init
bash scripts/verify-macos-vm.sh --disposable
```

If the guest lacks a Docker engine but already has Homebrew, prepare it first:

```sh
bash scripts/prepare-macos-vm.sh --disposable
DOCKER_CONTEXT=colima-codyssey-verify bash scripts/verify-macos-vm.sh --disposable
```

Preparation installs Docker CLI, Compose, Buildx, Colima, QEMU, Python, and Chrome on
Homebrew-based guests. On Intel guests with MacPorts, install the tools before running
preparation using the [Fusion instructions](#intel-with-vmware-fusion-pro). Preparation starts a
dedicated `codyssey-verify` Colima profile using QEMU TCG. The Linux architecture is x86_64
inside an Apple Silicon macOS guest and aarch64 inside an Intel macOS guest. Cross-architecture
emulation avoids nested hardware virtualization.
On Intel, the preparer allows up to ten minutes for Lima user-v2 address
resolution because the emulated ARM guest can reach DHCP after the default
two-minute deadline.
See [Colima's architecture and QEMU configuration](https://colima.run/docs/configuration/).
Preparation includes Lima's additional guest agents, required for
[cross-architecture port forwarding](https://lima-vm.io/docs/config/multi-arch/).
The emulation is slow; reserve at least 8 GiB of guest memory and enough guest disk for a 30 GiB
Linux disk and Docker images. Provisioning requires internet downloads and Homebrew's normal install
permissions. It does not install Homebrew or OrbStack. Guest tool versions are resolved by Homebrew;
the application image and bootstrap tool pins remain those in this repository. This provisioning
step is intentionally mutable and is not a reproducible package snapshot: Homebrew may resolve newer
formula or cask versions on a later run.

Verification first runs `scripts/check.sh --native-python`, then runs the actual `init.sh` twice.
This mode runs `portable-browser-test.py`, `macos-setup-test.py`, `vm-orchestration-test.py`, `preinstalled-tools-test.py`, `installer-recovery-test.py`, `options-test.py`, and `browser-configuration-test.py` natively on the macOS guest
with synthetic state and fake commands. The pinned Linux container runs the Bash/zsh bootstrap suites
and always runs `vm-guest-test.py` (with a bounded 120-second case timeout for emulated subprocess startup), whose fake Homebrew, Colima, and Docker guest boundaries must never
execute natively on macOS. No checks are omitted; native execution of the eight safe Python suites avoids
expensive process startup under x86 emulation. The default `scripts/check.sh` runs all suites inside
the isolated container.
Verification checks the
unauthenticated state, Bash/client tools, TUN device and home mount, GOST API and UI HTTP readiness,
and the single shell activation block. It then runs the private local Headscale lab for ephemeral lifecycle, short-name DNS and terminal tools, verifies a fresh portable browser profile and relaunch, and verifies the real Dock launcher twice plus live shortcut registration. Input-method approval and physical Hangul typing remain an interactive check; the unattended VM does not wait for or bypass macOS approval dialogs. Run the full live preference verifier separately in an approved desktop session. GOST API readiness also checks whether this Docker environment makes
the Linux host's loopback listener accessible from the macOS guest; failure is a real incompatibility,
not a simulated success. UI HTTP readiness does not prove browser rendering or API interaction.

The verifier uses an allowlisted temporary copy under the guest home, a synthetic GOST configuration,
an explicitly empty exported key, and a randomized Compose project. Before Docker workload use, it
rejects `DOCKER_HOST`, resolves and freezes `DOCKER_CONTEXT`, and accepts only an absolute local
Unix-socket endpoint. It clears caller Compose-file and environment-file overrides. It refuses
existing production container names or occupied management ports; rejected resources are not cleaned up because the verifier does not own them.
It removes only its own containers on exit. Cleanup failure retains the private
working directory, reports its location, returns nonzero, and suppresses terminal PASS. Docker's
built images and check image remain cached. Guest preferences and `.zshrc` remain modified. The Dock launcher targets the retained source tree, and the verifier checks its `--list` command before removing the temporary workload. To stop
or remove the prepared Docker VM afterward:

```sh
colima stop --profile codyssey-verify
# Discard that profile's Linux disk and Docker cache when no longer needed:
colima delete --profile codyssey-verify
```

### Create a new macOS VM and run everything

The same command selects Tart on Apple Silicon and VMware Fusion Pro on Intel.

#### Apple Silicon with Tart

On an Apple Silicon Mac running macOS 14 or newer, install mise first. The script installs
the configured Tart version automatically; no separate `mise use` or Tart installation is needed.

Choose a reviewed, stopped local Tart base VM with Homebrew, Tart Guest Agent, and a logged-in desktop
user. A registry image can also be used, but must be pinned to its actual OCI digest; mutable registry
tags are rejected. The guest macOS version must be compatible with the host. Non-vanilla Cirrus Labs
images include Guest Agent; see [Tart's quick start](https://tart.run/quick-start/) and
[Guest Agent documentation](https://tart.run/blog/2025/06/01/bridging-the-gaps-with-the-tart-guest-agent/).

```sh
cd environment/codyssey-init
# Clone a reviewed local base into a new writable VM:
bash scripts/create-macos-vm.sh --image reviewed-macos-base

# Or use this pinned Cirrus Labs base (check host compatibility first):
bash scripts/create-macos-vm.sh \
  --image ghcr.io/cirruslabs/macos-tahoe-base@sha256:87f3aa5ce21b5c876268f233bdfecf38b4c2a8116fe9bbb718e714cbae187377 \
  --name codyssey-environment-test
```

Tart assigns four CPUs and 8 GiB of memory to the clone and keeps its base cache. Allow substantial
download time and disk space for the base and emulated Linux guest. The published quick-start image
is approximately 25 GB before guest provisioning.

Every host Tart invocation, including the long-running VM process, uses
`mise -C <environment-directory> -E vm exec tart -- tart`, independent of the caller's working
directory. The version is declared only in `mise.vm.toml`. The explicit `mise install tart`
also works with automatic installation disabled and does not install unrelated tools such as just.

#### Intel with VMware Fusion Pro

Install a Fusion Pro version compatible with the Intel host and the macOS guest. Broadcom limits
support for newer macOS guests. Verify that the base boots and VMware Tools reports its IP before
using it here. [Broadcom macOS guest support policy](https://knowledge.broadcom.com/external/article/301109/vmware-discontinuation-of-latest-macos-a.html).

To create a base from scratch, use a versioned Apple installer. For example, this command
downloads macOS Sequoia 15.8.3 (build 24H241) to `/Applications` when that version is still
offered by Apple. It does not upgrade the host.

```sh
softwareupdate --list-full-installers
softwareupdate --fetch-full-installer --full-installer-version 15.8.3
```

Build bootable media with Apple's `createinstallmedia`. The command needs host administrator
authorization and erases the specified volume. Use a fresh image in a private working
directory, with room for the installer image and its ISO conversion.
[Apple bootable installer instructions](https://support.apple.com/en-us/101578).

```sh
(
set -eu
umask 077
storage="${CODYSSEY_FUSION_STORAGE:-$HOME/.local/share/codyssey/fusion}"
mkdir -p "$storage/installers" "$storage/runs"
iso="$storage/installers/Sequoia-24H241.iso"
if [ -s "$iso" ]; then
  printf '%s\n' "$iso"
  exit 0
fi
lab=$(mktemp -d "$storage/runs/sequoia.XXXXXX")
mount="$lab/installer-volume"
mkdir "$mount"
hdiutil create -size 18g -type SPARSE -layout SPUD -fs HFS+J \
  -volname CodysseyInstaller "$lab/sequoia.sparseimage"
hdiutil attach -nobrowse -mountpoint "$mount" -plist "$lab/sequoia.sparseimage" \
  > "$lab/attachment.plist"
device=$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:dev-entry' "$lab/attachment.plist")
trap 'if [ -n "$device" ]; then hdiutil detach "$device"; fi' EXIT
sudo "/Applications/Install macOS Sequoia.app/Contents/Resources/createinstallmedia" \
  --volume "$mount" --nointeraction
hdiutil detach "$device"
device=
hdiutil convert "$lab/sequoia.sparseimage" -format UDTO -o "$lab/sequoia"
mv -n "$lab/sequoia.cdr" "$iso"
printf '%s\n' "$iso"
)
```

In Fusion, choose **File > New > Install from disc or image**, then select the ISO
from the storage directory's `installers/` subdirectory. Choose an Apple macOS guest if prompted and
let the wizard create its virtual hardware. Set four vCPUs, 8 GiB RAM, and an 80 GiB
growable disk. The Broadcom community procedure attaches a bootable DMG directly.
The command above converts the bootable image to UDTO for use as an ISO.
[Fusion installer-image procedure](https://community.broadcom.com/vmware-cloud-foundation/question/installer-app-not-accepted-for-installing-macos-vm).

Use NAT, disable shared folders and host folder
mirroring, and keep the base and clone on a volume with room for both virtual disks and
guest Docker images. Store the VM bundle in a persistent directory such as
`~/.local/share/codyssey/fusion/bases/` so installation can survive a host restart.
In the installer, open Disk Utility and choose **View > Show All Devices**.
Select **VMware Virtual SATA Hard Drive Media**, check that its capacity matches the
configured guest disk, and erase it as APFS with a GUID partition map. Quit Disk Utility
and select the resulting volume in the installer. Create a local disposable
administrator account during Setup Assistant. Use `vmuser` as its short name. Generate
a unique password per base with a password manager or `openssl rand -hex 24` in a
private terminal. Save it in the operator's password manager and enter it locally in
the guest console for Setup Assistant and administrative prompts. Avoid signing in
to a personal Apple account.
At the Welcome screen, before installing guest tools, save a checkpoint if you
want to return to the freshly configured desktop. Shut down the guest first to
avoid storing its RAM in the snapshot.

```sh
vmrun="/Applications/VMware Fusion.app/Contents/Library/vmrun"
vmx="/path/to/guest.vmx"
"$vmrun" -T fusion snapshot "$vmx" "Sequoia - initial setup complete"
"$vmrun" -T fusion listSnapshots "$vmx"
```

This account is created once per base. For an unmanaged Fusion VM, complete Setup
Assistant in the Fusion console. Apple's unattended Setup Assistant flow uses
Automated Device Enrollment and a device management service that creates a managed
administrator account. Start repeatable CLI verification from a prepared base with a
local account, VMware Tools, Remote Login, and an approved desktop session.
[Apple's Auto Advance requirements](https://support.apple.com/guide/deployment/automated-device-enrollment-management-dep73069dd57/1/web).

If the installer offers the volume and then reports that the installer is damaged,
open **Window > Installer Log** and record the failed operation. If the log reports
`OSISVerifyBaseSystemOperation` or `pkgdmg validation has failed`, keep the guest disk
and investigate the installer media. On the host, mount the ISO read-only and use
`hdiutil verify` on `BaseSystem/BaseSystem.dmg` and the installer app's
`Contents/SharedSupport/SharedSupport.dmg`. These checks validate image checksums.
The guest installer performs its own package validation.

If the attached installer fails package validation, standalone Apple Recovery offers
**Reinstall macOS**, which downloads the installation assets through the guest's NAT
connection. Use a compatible Apple `BaseSystem.dmg` from the host Recovery volume
and keep the formatted SATA target disk. Use `diskutil apfs list` to identify the
volume with the Recovery role and `diskutil mount readOnly <recovery-volume-id>`
to access it if it is unmounted. Find `BaseSystem.dmg` in the volume's system
directory and select the image for the intended macOS release. Power off the disposable
VM and run the following from its bundle to wrap the image as a VMware hard disk.

```sh
hdiutil convert /path/to/BaseSystem.dmg -format UDTO -o RecoveryMedia
bytes=$(stat -f %z RecoveryMedia.cdr)
test "$bytes" -gt 0 && test "$((bytes % 512))" -eq 0 || exit 1
cat > RecoveryMedia.vmdk <<EOF
# Disk DescriptorFile
version=1
encoding="UTF-8"
CID=fffffffe
parentCID=ffffffff
createType="monolithicFlat"
RW $((bytes / 512)) FLAT "RecoveryMedia.cdr" 0
ddb.adapterType = "lsilogic"
ddb.virtualHWVersion = "6"
EOF
```

In the powered-off lab VM's VMX, keep the existing target disk on `sata0:0`, replace
the CD/DVD device's `sata0:1.*` entries with the settings below, and connect the existing
NAT adapter. Start the VM with Fusion or the CLI.

```text
sata0:1.present = "TRUE"
sata0:1.fileName = "RecoveryMedia.vmdk"
sata0:1.startConnected = "TRUE"
sata0:1.mode = "independent-nonpersistent"
bios.hddOrder = "sata0:1,sata0:0"
```

To start the VM from a terminal, use:

```sh
"/Applications/VMware Fusion.app/Contents/Library/vmrun" -T fusion \
  start "/path/to/guest.vmx" gui
```

In the console, select **Reinstall macOS** and choose the guest's `Macintosh HD`.
If the installer reboots into the standalone Recovery menu, shut down from the
guest's Apple menu. With the VM powered off, set `sata0:1.present = "FALSE"` and
`bios.hddOrder = "sata0:0"` in the VMX, then restart to continue from the staged
installation on the target disk. Leave the Recovery disk disconnected when using
the installed guest as a base.

To monitor a running installation from a terminal, use `uv` and Fusion's `vmcli`:

```sh
storage="${CODYSSEY_FUSION_STORAGE:-$HOME/.local/share/codyssey/fusion}"
mkdir -p "$storage/runs"
run=$(mktemp -d "$storage/runs/watch.XXXXXX")
uv run --no-build scripts/watch-fusion-installer.py \
  --vmx "/absolute/path/to/base.vmx" --output-dir "$run"
```

The watcher defaults to one capture per minute for up to one hour. Use `--interval` and
`--timeout` to change those values in seconds. It keeps the latest `screen.png` and
`status.json` in the chosen directory. A `menu-candidate` means enough of the frame has changed from
the black boot background to inspect for the installer menu. Check the screenshot before interacting with it.
Once installation starts, use a new output directory and add
`--monitor --interval 180 --timeout 14400` to capture every three minutes for up to four hours.
In monitor mode, a `menu-candidate` is recorded and capture continues. Check the screenshot
for Setup Assistant or an installer error, then stop the watcher with Ctrl-C.
If screen capture fails and Fusion's inventory omits the VM, the watcher emits `not-listed`
and returns status 1. Confirm the actual power state before restarting or editing the VM.
A timeout returns 124. Store the watch directory outside
the repository and use a separate directory for each watcher.

After installation, eject the macOS installer disk and install VMware Tools from Fusion's
**Virtual Machine** menu. If Fusion lacks the macOS Tools image, attach Broadcom's
[Darwin Tools ISO](https://packages-prod.broadcom.com/tools/frozen/darwin/darwin.iso)
as the guest CD/DVD and install the VMware-signed package inside the guest.
The same package can be installed from a guest terminal. Use the package path
shown by `find` and authenticate the guest administrator when `sudo` prompts.

```sh
find "/Volumes/VMware Tools" -name "VMware Tools.pkg" -print
sudo /usr/sbin/installer -pkg "/path/to/VMware Tools.pkg" -target /
```

If macOS blocks the signed VMware extension, review the prompt in the guest's
**Privacy & Security** settings and restart the guest after approval. From the
host, use `vmrun -T fusion getGuestIPAddress /path/to/guest.vmx` to confirm that
the VMware Tools service is running.

In an already provisioned automation environment, a secret manager can supply the
administrator password on standard input to `sudo -S`. Keep that credential
in the secret manager and use a scoped secret reference. The repeatable
verification command itself authenticates with the dedicated SSH key.
Verify the version and architecture inside the guest with
`sw_vers` and `uname -m`. Install Xcode Command Line Tools with `xcode-select --install`.
For a new Intel guest, install [MacPorts](https://www.macports.org/install.php) and
prepare the verification tools as follows:

```sh
sudo /opt/local/bin/port install lima +additional_guestagents
sudo /opt/local/bin/port install colima docker docker-compose-plugin docker-buildx-plugin python313 nodejs24
sudo /opt/local/bin/port select --set python3 python313
```

Install Google Chrome from Google in `/Applications` or the guest user's
`~/Applications`. Confirm `docker compose version` and `docker buildx version`
as the desktop user before running verification. The verifier uses the Intel
MacPorts tools already installed in the guest. Existing Homebrew-based guests can
continue to use Homebrew.

The verifier needs an active desktop session. For unattended runs, open
**System Settings > Users & Groups** in the disposable guest and set
**Automatically log in as** to the lab account. For attended runs, sign in to the
clone while the verifier waits for the desktop. Enable Remote Login for the
disposable account only. Use a dedicated
host SSH key for the lab and add only its public key to the guest user's
`~/.ssh/authorized_keys`. The verifier uses SSH public-key authentication and a
pinned host key. Keep the console password out of the repository, shell arguments,
and verification logs. The guest and its clones inherit the local account, so use
the base and its credentials only for this lab.

On the host, create a dedicated key once and load it in the SSH agent before running
verification. The example prompts for a key passphrase at creation and when adding
the key to a new agent session.

```sh
(
set -eu
umask 077
credentials="$HOME/.local/share/codyssey/fusion/credentials"
mkdir -p "$credentials"
key="$credentials/id_ed25519"
if [ ! -e "$key" ] && [ ! -e "$key.pub" ]; then
  ssh-keygen -t ed25519 -C codyssey-fusion-lab -f "$key"
fi
test -f "$key" && test -f "$key.pub"
ssh-add "$key"
)
```

Copy the single line from `id_ed25519.pub` into the guest account's
`~/.ssh/authorized_keys`. Set `~/.ssh` to mode `0700` and
`authorized_keys` to `0600` in the guest. Keep the private key on the host.

Before using an existing base, check that it meets the same requirements and has no active
Docker engine. The script disables shared folders on the clone before boot.
The runner uses a temporary LaunchAgent in the logged-in user's Aqua session. Before installing
guest tools, it checks that the Aqua job can see the Dock and that macOS has granted Accessibility
access to the process running the Swift check. From a copy of this directory in the disposable
base, use the same Aqua job to ask macOS for access:

```sh
/usr/bin/python3 scripts/vm-aqua-exec.py 60 \
  /usr/bin/swift "$PWD/scripts/verify-dock-ui.swift" --request-access
```

Use the guest's System Settings to grant access when macOS prompts. Rerun the command with
`--preflight` to check access before shutting down the base. A failed preflight during host
verification retains the clone for inspection.

Create a dedicated host known-hosts file with the reviewed base's SSH host public key. For example,
copy the public key from `/etc/ssh/ssh_host_ed25519_key.pub` via the base VM console, then put
`codyssey-fusion ssh-ed25519 <public-key>` on a line in that file. The clone inherits the base's
host key. The host uses OpenSSH's default identity files or an SSH agent for authentication.

From a writable directory with room for the full clone, run:

```sh
CODYSSEY_FUSION_GUEST_USER=vmuser \
CODYSSEY_FUSION_KNOWN_HOSTS="$HOME/.ssh/codyssey-fusion-known-hosts" \
bash /path/to/codyssey-public/environment/codyssey-init/scripts/create-macos-vm.sh \
  --image "/path/to/Reviewed Base.vmwarevm/Reviewed Base.vmx" \
  --name codyssey-environment-test
```

The script creates `codyssey-environment-test.vmwarevm` in the current directory. To build a
preinstalled base, invoke `create-preinstalled-macos-image.sh` with the same Fusion environment
and source options. For a later `--preinstalled` run, pass the resulting bundle's `.vmx` as
`--image`. The Fusion adapter uses
`/Applications/VMware Fusion.app/Contents/Library/vmrun` by default. Set
`CODYSSEY_FUSION_VMRUN` to the absolute executable path for another installation location.
Use a Fusion release with `vmcli` next to `vmrun`. The adapter uses `vmcli ConfigParams SetEntry`
to disable HGFS and set the share count to zero while the clone is powered off.
[VMware Fusion Pro 13 documentation](https://techdocs2-prod.adobecqms.net/content/dam/broadcom/techdocs/us/en/pdf/vmware/desktop-hypervisors/fusion/vmware-fusion-pro-13.pdf).

#### Reuse the prepared Fusion base

After guest setup and the desktop preflight pass, eject the installer and Tools images,
turn off any temporary VNC console, and shut down macOS. Keep the entire powered-off VM
bundle together, including its VMX, virtual disks, and NVRAM. A private location such as
`~/.local/share/codyssey/fusion/bases/` keeps the base available across host restarts.
Use the base VMX with `--image` for each run. The verifier creates a full clone and
applies setup changes inside that clone.

For external storage, use a writable APFS volume and move the complete powered-off
bundle there. Open the moved VMX in Fusion and choose **I moved it** if prompted,
then confirm the guest boots and its snapshots are present. Keep the installer and
watcher output on the same SSD if internal space is limited. Run the verification
command from a directory on the SSD because it places the full clone in the current
directory. For example, if the volume is named `Codyssey VM`:

```sh
export CODYSSEY_FUSION_STORAGE="/Volumes/Codyssey VM/Codyssey-Fusion"
test -d "$CODYSSEY_FUSION_STORAGE/bases" || exit 1
mkdir -p "$CODYSSEY_FUSION_STORAGE/verification"
cd "$CODYSSEY_FUSION_STORAGE/verification" || exit 1
```

Keep the versioned ISO for reinstalling from scratch. To recover the prepared base after
host storage loss, copy its complete powered-off bundle to separate storage. Preserve
the corresponding SSH host-key pin on the host with the lab's connection configuration.

#### Verification and cleanup

Tart boots the clone headlessly. Fusion starts it through the Fusion app so the
running inventory and guest transport are available, and may show a first-start
notice in the console. Both backends retry the guest connection for six minutes.
On Fusion, the desktop preflight has a one-minute job timeout and the full Aqua verification
has a six-hour job timeout.
They stream the same allowlisted environment files into the guest, then run the same provisioning
and verification scripts. Docker runs only inside the disposable guest. The transfer excludes
`.env`, user-edited GOST configuration, and host credentials. The host script owns sequencing,
retention policy, and the final exit status. Each adapter owns its VM identifier and translates
clone, boot, guest execution, file transfer, shutdown, and deletion into hypervisor commands.

The guest refuses an already-running verification profile. For host-managed runs, the guest records
ownership before starting Colima so teardown can discover it even if the preparation reply is lost.
Cleanup stops the owned profile before stopping macOS so the nested Linux disk is flushed.
If Colima shutdown cannot be confirmed, the host leaves the clone available for recovery without
requesting macOS shutdown. The VM is retained for inspection by default. Pass `--delete-on-success` to delete the new VM
after verification and shutdown succeed. A failed shutdown prevents
deletion and terminal PASS. Existing source VMs and destinations are left alone. The script
prints commands to open or delete a retained VM after a confirmed stop.

Host orchestration tests require only Python and fake commands; they do not create VMs:

```sh
python3 tests/vm-orchestration-test.py
```

These orchestration tests do not establish a successful real VM run. The Linux container cannot
exercise Tart, Fusion, Colima, Homebrew, macOS defaults, Chrome rendering, guest readiness timing, or QEMU port
forwarding on a real Mac. Real guest success is reported only when provisioning, Docker checks, both
bootstrap passes, live preference verification, and cleanup all finish successfully on supported
macOS hosts.
