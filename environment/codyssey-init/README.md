# Codyssey macOS tailnet bootstrap

This is a shared macOS workstation bootstrap for course participants. It installs or reuses
Ghostty as a basic application. Personal Tailnet services and workstation preferences are
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
Ghostty is part of the default macOS application setup. A valid existing system or per-user
Ghostty is reused without replacement; otherwise the checksum-pinned universal Ghostty 1.4.0
DMG is installed under `~/Applications` without sudo or launching it. The complete bundle is
staged before publication, so a failed copy can be retried. See the
[official binary installation guide](https://ghostty.org/docs/install/binary) and the
[checksum source](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/g/ghostty.rb).
OrbStack windows are left under the user's control; the bootstrap does not hide them.

Each runtime invocation prints its private diagnostic log path under
`~/Library/Logs/codyssey-init/run.*` (directory mode `0700`, files `0600`). Logs survive
success, failure, and cancellation. Attach that file to a problem report, together with the
command you ran, the repository revision (`git rev-parse HEAD` for a checkout), and the
visible error. The shareable log records UTC timestamps, macOS/architecture, stage outcomes,
and exit codes. It deliberately excludes command output, environment dumps, auth input,
Tailscale login URLs, and container logs. Detailed tool diagnostics still appear in the
terminal on failure. Review any extra terminal output before sharing it. Delete old log files
manually when no longer needed; no automatic upload occurs. If logging is unavailable, a
warning is printed and setup continues. Remote download/preflight failures occur before the
runtime log exists, so include their terminal error separately.

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

When personal macOS preferences are selected, this environment disables text automation and configures **Gureum 1.13.2 Hangul 2-set**
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

The reference environment is macOS 15.7.5 on x86_64 with Gureum 1.13.2 installed at
`/Library/Input Methods/Gureum.app`. This is an environment bootstrap, not a general-purpose macOS
configuration tool. On a fresh machine, `scripts/install-gureum.sh` downloads the exact 1.13.2 package,
verifies its pinned SHA-256, and extracts it into `~/Library/Input Methods/Gureum.app` without sudo.
An existing matching installation is reused. Swift and the Xcode Command Line Tools are required for
Carbon registration and selection.

`enable-korean.swift` registers the installed app, enables its parent source
`org.youknowone.inputmethod.Korean` and Hangul mode `org.youknowone.inputmethod.Gureum.han2`, and attempts
to select Hangul. The legacy parent ID differs from the app's bundle ID,
`org.youknowone.inputmethod.Gureum`. After successful Gureum selection, it disables the Apple Korean
sources added by the earlier bootstrap. Activation requests can return success before the user approves
the macOS dialog. The helper stays alive for up to 120 seconds per source, services its run loop,
and waits for actual activation before enabling the next source. Choose Allow when prompted.
Already-enabled sources are not prompted again. Selection is verified against the current input source;
timeout or selection failure reports an actionable error while other preference groups continue. No logout is performed or required
by the setup flow. To retry input setup in the current session:

```sh
bash macos-setup.sh --input-only
```

Control-Space uses symbolic hotkey 60 with parameters `[65535, 49, 262144]`; Control-Shift-Space uses 61
with `[65535, 49, 393216]`. The old value `786432` was Control-Option-Space. After synchronizing preferences through CFPreferences,
the setup registers and enables the live bindings through SkyLight, waits for asynchronous application,
and verifies their values and enabled state. These private APIs target the reference macOS version;
missing symbols produce an error for this group while other setup groups continue.
Loaded shortcut registration does not prove physical key handling; test both Korean and English in a
focused text field. The setup does not automatically replace Gureum with Apple Korean when Caps Lock fails.
See [HANDOFF.md](HANDOFF.md) for installed input-source details and fresh-VM steps.

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
layout, removes only the exact Korean input mode and symbolic-hotkey entries 60/61/64/65 from its
baseline-derived fixture, clears Dock pins, and enables all nine text-automation settings. It never
inserts a synthetic input source. It then applies the setup twice and verifies parsed plist values,
including exact Dock entries, typed hotkey parameters, and preservation of unrelated input sources
and shortcuts. It will not run without both Darwin and this exact opt-in:

```sh
CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 python3 verify-macos-setup.py
```

`--desktop-only` snapshots only Dock, applies the desktop setup twice, verifies the real launcher
with `--list`, and preserves keyboard/text preferences. The unattended VM uses this mode plus
independent live shortcut verification, so input-source approval cannot block its service tests.
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

Install mise on the host; Tart does not need to be installed or configured globally.
The host VM scripts select the opt-in `mise.vm.toml` environment using `mise -E vm`,
install only its pinned Tart 2.40.1, then run Tart through mise. The platform check runs
before installation and rejects Linux, Intel Macs, and macOS older than 14.
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
2.2.4 and Ghostty 1.4.0 in `~/Applications`, and Gureum 1.13.2 in `~/Library/Input Methods` without launching onboarding,
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

This mode first inspects the real OrbStack/Gureum/Chrome/Ghostty bundles, checks Gureum's version, executes
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

### An existing disposable VM

With Docker already running, Python 3.10+, Chrome, a logged-in desktop user, and ordinary macOS
preference domains present, run inside the guest:

```sh
cd environment/codyssey-init
bash scripts/verify-macos-vm.sh --disposable
```

If the Apple Silicon guest lacks a Docker engine but already has Homebrew, prepare it first:

```sh
bash scripts/prepare-macos-vm.sh --disposable
DOCKER_CONTEXT=colima-codyssey-verify bash scripts/verify-macos-vm.sh --disposable
```

Preparation installs Docker CLI, Compose, Buildx, Colima, QEMU, Python, and Chrome when absent. It starts a
dedicated `codyssey-verify` Colima profile with x86_64 Linux emulated on arm64 using QEMU TCG. This
avoids nested hardware virtualization, which [Tart does not support for macOS guests](https://tart.run/faq/).
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
This mode runs `portable-browser-test.py`, `macos-setup-test.py`, `vm-orchestration-test.py`, `preinstalled-tools-test.py`, `installer-recovery-test.py`, and `options-test.py` natively on the macOS guest
with synthetic state and fake commands. The pinned Linux container runs the Bash/zsh bootstrap suites
and always runs `vm-guest-test.py` (with a bounded 120-second case timeout for emulated subprocess startup), whose fake Homebrew, Colima, and Docker guest boundaries must never
execute natively on macOS. No checks are omitted; native execution of the six safe Python suites avoids
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

The host script clones a fresh VM, assigns four CPUs and 8 GiB memory, boots it headlessly, waits up
to six minutes for Guest Agent, transfers the allowlisted environment files through `tart exec`,
prepares guest Docker, and runs the same existing-VM verifier. It never shares the host home, sends
`.env` or user-edited GOST configuration, passes a Tailscale key, or enables a nested hypervisor.
Tart automatic cache pruning is disabled for this run, and an existing destination VM is never
overwritten. Allow substantial download time and disk space for the macOS base and emulated Linux
guest. The published quick-start image is approximately 25 GB before guest provisioning.

Every host Tart invocation, including the long-running VM process, uses
`mise -C <environment-directory> -E vm exec tart -- tart`, independent of the caller's working
directory. The version is declared only in `mise.vm.toml`. The explicit `mise install tart`
also works with automatic installation disabled and does not install unrelated tools such as just.
The host needs no Docker engine or Docker CLI. Docker is installed and used
only inside the disposable macOS guest for the environment tests.

If guest preparation starts the dedicated Colima profile and a later readiness check fails, the guest
preparer attempts to stop that owned profile while preserving the original failure status. After
provisioning, host cleanup shuts down Colima before stopping macOS so the nested Linux disk is
flushed. A Tart stop failure is reported, prevents deletion, and is never described as stopped. On
completion or failure the new VM is retained for inspection. Pass
`--delete-on-success` to delete only this newly created VM after successful verification. Failed VMs
are always retained; Tart's downloaded base cache is retained too. The script prints commands to open
or delete its VM after a confirmed stop. Terminal PASS is printed only after required cleanup has
succeeded. Existing source VMs are never stopped or deleted.

Host orchestration tests require only Python and fake commands; they do not create VMs:

```sh
python3 tests/vm-orchestration-test.py
```

These orchestration tests do not establish a successful real VM run. The Linux container cannot
exercise Tart, Colima, Homebrew, macOS defaults, Chrome rendering, Guest Agent timing, or QEMU port
forwarding on a real Mac. Real guest success is reported only when provisioning, Docker checks, both
bootstrap passes, live preference verification, and cleanup all finish successfully on supported
macOS hosts.
