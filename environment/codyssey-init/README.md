# Codyssey macOS tailnet bootstrap

This directory prepares a repeatable Tailscale and GOST environment for a macOS workstation that
already has a working Docker Engine and Compose v2. It builds a pinned Tailscale image with Bash and
other terminal tools, starts the tailnet and local GOST management services, and optionally applies a
small set of macOS preferences.

The bootstrap does not install Docker, authenticate to Tailscale by itself, or prove that a remote
tailnet is reachable. Those remain explicit user and environment boundaries. It can install a pinned,
checksum-verified `mise` binary when `mise` is missing.

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

The root entry point must be published to GitHub before that new URL is available.
That command streams the root wrapper from mutable `main`, so use it only when that
latest wrapper is trusted. By default, the wrapper downloads the Bash bootstrap from
the reviewed commit `7a4feac9bbf6aa3c547141b0cfbbfb76bbb5168b` into a temporary file before
executing it. `CODYSSEY_INIT_REF` may select another reviewed full 40-character
lowercase commit, and `CODYSSEY_INIT_BASE_URL` may select another reviewed HTTPS raw
source. Run `sh init.sh --help` or `sh init.sh --docs` without network access for
usage and the documentation URL at the selected revision.

To pin and buffer the root wrapper itself before execution, use:

```sh
(
  ref=REPLACE_WITH_A_REVIEWED_COMMIT_CONTAINING_ROOT_INIT
  installer=$(mktemp)
  trap 'rm -f "$installer"' EXIT HUP INT TERM
  curl -fsSL "https://raw.githubusercontent.com/mjy9088/codyssey-public/$ref/init.sh" -o "$installer" &&
    sh "$installer"
  status=$?
  rm -f "$installer"
  exit "$status"
)
```

The nested POSIX entry point remains available for backward compatibility:

```sh
curl -fsSL https://raw.githubusercontent.com/mjy9088/codyssey-public/main/environment/codyssey-init/install.sh | sh
```

It resolves `main` once when `CODYSSEY_INIT_REF` is absent. Prefer an explicit
reviewed full commit when using that older entry point.

Remote mode stages the complete reusable runtime, including `init.sh`, `verify-macos-setup.py`, and
runtime libraries, before copying anything into
`${CODYSSEY_INIT_DIR:-$HOME/.local/share/codyssey-init}`. It refuses to overwrite a different
installer file during a full preflight. Failed downloads leave the target untouched and remove their
staging directory. Existing `.env` and `gost/gost.yaml` files are preserved. A local checkout runs in
place and rejects a different `CODYSSEY_INIT_DIR`, avoiding a partial or ambiguous copy.

## Prerequisites

- macOS with OrbStack or another Docker Engine exposing Compose v2
- `zsh`, `curl`, and ordinary terminal access
- access to `/dev/net/tun` and permission for Docker to grant `NET_ADMIN` and `NET_RAW`
- optionally, a Tailscale auth key or permission to complete browser login

The script reuses `mise` from the current path or `$HOME/.local/bin`. When it is missing, macOS arm64
and x86_64 use the official `mise` v2026.10.5 release binary with a repository-pinned SHA-256 value.
No mutable shell installer is executed. Automatic installation requires `curl`, `shasum`, `cut`,
`install`, and `mktemp`; unsupported systems and architectures fail clearly. The repository-owned
`mise.toml` pins `just` to `1.43.0`. `next-script.zsh` runs under real zsh, trusts the local config,
explicitly installs `just@1.43.0`, and refreshes the shell environment with `mise env -s zsh` before
Compose starts.

`init.sh` checks that Docker is running, adds the user-local `mise` path and zsh activation block once,
and launches `next-script.zsh` as an interactive zsh script with terminal input restored when a controlling terminal is available. Secret input is read directly and silently from `/dev/tty`.

## Authentication and startup

An exported `TS_AUTHKEY`, including an intentionally empty value, takes precedence and is passed to
Compose without creating or changing `.env`. An existing `.env` is also preserved. Otherwise, when a
terminal is available, the bootstrap asks for either:

- a Tailscale auth key;
- a pasted Tailscale install/up command containing an auth key; or
- a blank line to use the browser-login path.

Pasted text is never executed. A complete `tskey-auth-` token using the documented alphanumeric,
underscore, and hyphen alphabet is extracted; a malformed token is rejected rather than partially
matched. Terminal echo is restored from the exact saved `stty -g` state on success, failure, and
signals. If no controlling terminal exists, the script safely creates an empty mode-`0600` `.env` and
continues to the browser-login path without attempting to read or truncate `/dev/tty`.

Compose is started with a build:

```sh
docker compose up -d --build
```

The bootstrap waits for all three containers and a Tailscale `Running` or `NeedsLogin` state. A
`NeedsLogin` state is not reported as a connected tailnet: the script extracts and prints the actual
`https://login.tailscale.com/...` authentication URL from Tailscale's output. The entry point keeps the daemon alive throughout browser
authentication, avoiding the upstream container wrapper's 60-second startup timeout. It reads the current URL from status, with the latest logged URL as a fallback, and waits up to 60 seconds
for that URL because `NeedsLogin` can appear before the URL is available, then fails with a command
to inspect the logs if no URL is available:

```sh
docker compose logs tailscale
```

It then waits for the local GOST UI and opens Chrome when available, falling back to the default
portable Tailnet browser by default (or the installed browser with `CODYSSEY_BROWSER=system`). Interactive runs finish in zsh with `mise` and `just` available. The URL is:

<http://localhost:18081/?api=http%3A%2F%2Flocalhost%3A18080>

Set `CODYSSEY_OPEN_BROWSER=0` for unattended or headless runs. Both URLs are still printed, but no
browser is launched. VM verification uses this mode to avoid first-launch browser dialogs blocking
the bootstrap.

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

Tailscale uses `--state=mem:` and registers as an ephemeral node. Restarting it requires fresh
authentication unless a reusable auth key is configured. Existing old state volumes are left untouched. The GOST API listens only on
`127.0.0.1:18080`, and the UI is published only on `127.0.0.1:18081`. No forwarding service is enabled
by default. Add services with loopback listener addresses unless deliberate external exposure is
required.

## Tailnet shell and `just`

Open Bash in the Tailscale container with either command:

```sh
bash tailnet.sh
just
just bash
```

With arguments, `tailnet.sh` executes those exact arguments instead of prepending Bash:

```sh
bash tailnet.sh ssh user@100.64.0.10
bash tailnet.sh bash -lc 'command-one | command-two'
```

Arguments, spaces, and the command exit status are preserved. Interactive terminals retain a TTY;
redirected calls use Compose's non-TTY mode. Bash is probed through `sh -c 'command -v bash'`, and an
old image is rebuilt only when Bash is the requested command (implicitly through no arguments or
explicitly as the first argument). Arbitrary commands are never probed, prefixed, or rebuilt. Existing old state volumes are not removed.

## Portable Tailnet browser

On macOS the bootstrap now opens a portable **Chrome for Testing 155.0.8059.39** with the Tailnet
extension loaded automatically. No browser installation, Web Store visit, or Load unpacked step is
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

The browser uses its own profile and extension copy under
`~/Library/Application Support/codyssey-init/`. Tailnet routing enables automatically on the first
launch; later launches preserve the user's routing choice. The extension routes MagicDNS names,
`.ts.net` names, Tailscale IPs, and private IPv4 destinations. Public websites stay direct. Its popup
can switch to All websites or disable routing. It needs only the `proxy` permission, and does not
authenticate Tailscale or provide a system-wide VPN. Keep the Tailscale container running and logged in.

The version and archive integrity pins live in `scripts/browser-version.sh`. The browser does not
auto-update; update those pins deliberately to adopt another release. Only x86_64 has been exercised
with a real browser here; the arm64 archive was downloaded and its checksum recorded, and architecture
selection is covered by synthetic tests. The launcher can override its private locations with
`CODYSSEY_BROWSER_CACHE_DIR` and `CODYSSEY_BROWSER_SUPPORT_DIR`.

Use `CODYSSEY_BROWSER=system` to keep the installed-browser behavior. `CODYSSEY_OPEN_BROWSER=0`
skips browser downloads and launches during bootstrap. To install the extension into ordinary Chrome,
run `just chrome-extension`, enable Developer mode, click Load unpacked, and select the printed
`chrome-extension` directory. That ordinary installation starts with routing off.

Chrome for Testing supports [automatic extension loading](https://groups.google.com/a/chromium.org/g/chromium-extensions/c/1-g8EFx2BBY/m/S0ET5wPjCAAJ).
The browser archives come from [Google's Chrome for Testing project](https://github.com/GoogleChromeLabs/chrome-for-testing).
See [the extension documentation](chrome-extension/README.md) for routing details and troubleshooting.
The SOCKS proxy must be reachable from macOS at `127.0.0.1:1055`; this has been verified on the current
OrbStack installation. Other Docker engines may need port forwarding from their Linux VM.

## Optional macOS preferences

This environment uses **Gureum 1.13.2 Hangul 2-set** by default. Other preferences are opt-in and nonfatal:

```sh
CODYSSEY_MACOS_SETUP=1 bash init.sh
```

`macos-setup.sh` refuses non-Darwin systems and never uses `sudo`. Before each independent preference
group, it creates a private per-run backup under
`~/Library/Application Support/codyssey-init/macos-backups/`. It then:

- disables macOS text automation;
- only when both Terminal and Google Chrome exist, replaces Dock app pins with those two apps,
  hides recent items, and removes folder stacks; otherwise the entire Dock group is left unchanged;
- preserves unrelated input sources while adding Gureum Hangul 2-set once;
- merges typed symbolic-hotkey entries 60 and 61 for Control-Space and Control-Shift-Space while
  preserving unrelated shortcuts; and
- restarts only the current user's Dock process.

The reference environment is macOS 15.7.5 on x86_64 with Gureum 1.13.2 installed at
`/Library/Input Methods/Gureum.app`. This is an environment bootstrap, not a general-purpose macOS
configuration tool. On a fresh machine, `scripts/install-gureum.sh` downloads the exact 1.13.2 package,
verifies its pinned SHA-256, and extracts it into `~/Library/Input Methods/Gureum.app` without sudo.
An existing matching installation is reused. Swift and the Xcode Command Line Tools are required for
Carbon registration and selection; the script does not silently substitute Apple's input method.

`enable-korean.swift` registers the installed app, enables its parent source
`org.youknowone.inputmethod.Korean` and Hangul mode `org.youknowone.inputmethod.Gureum.han2`, and attempts
to select Hangul. The legacy parent ID differs from the app's bundle ID,
`org.youknowone.inputmethod.Gureum`. After successful Gureum selection, it disables the Apple Korean
sources added by the earlier bootstrap. A freshly registered input method may require logout/relogin:
selection error `-50` was observed on this machine. The bootstrap reports the pending session step
rather than claiming the physical shortcut works. After logging back in, rerun:

```sh
bash macos-setup.sh --input-only
```

Control-Space uses symbolic hotkey 60 with parameters `[32, 49, 262144]`; Control-Shift-Space uses 61
with `[32, 49, 393216]`. The old value `786432` was Control-Option-Space. After importing preferences,
the setup reads them back to synchronize the preference cache, then calls this reference environment's
Apple helper, `/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u`.
This is an environment-specific private helper, and its availability is a prerequisite for live reload.
Loaded shortcut registration does not prove physical key handling; test in a focused text field after
logout/relogin. See [HANDOFF.md](HANDOFF.md) for installed input-source details and fresh-VM steps.

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

### Destructive live preference verifier

`verify-macos-setup.py` is a deliberately destructive live test requiring Python 3.10 or newer. It
privately snapshots every preference domain before any write, requires an existing Latin keyboard
layout, removes only the exact Korean input mode and symbolic-hotkey entries 60/61 from its
baseline-derived fixture, clears Dock pins, and enables all nine text-automation settings. It never
inserts a synthetic input source. It then applies the setup twice and verifies parsed plist values,
including exact Dock entries, typed hotkey parameters, and preservation of unrelated input sources
and shortcuts. It will not run without both Darwin and this exact opt-in:

```sh
CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 python3 verify-macos-setup.py
```

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
successful, failed, repeated, and conflicting immutable remote installs; preflight atomicity and
staging cleanup; verified missing-`mise` installation; exported-key and existing-`.env` precedence;
real-zsh execution; exact terminal-state restoration; browser-login URL handling; argument and exit
status preservation; and Bash-only rebuild scope. The same command also runs stateful macOS tests for
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

`docker compose down` stops the ephemeral node. This project no longer creates a Tailscale state
volume; any volume from an older installation remains untouched.

## Verification in a macOS VM outside the classroom

These scripts verify only this environment bootstrap. They use real Docker services and real macOS
preferences without an auth key. Tailscale must remain in `NeedsLogin`; browser launching is disabled
and authentication is never completed. No coursework, remote tailnet access, or authenticated forwarding is
tested. The VM must be disposable: verification changes its user's `.zshrc`, Dock, keyboard settings,
and text preferences. Successful preference verification leaves the requested settings applied.

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
This mode runs only `macos-setup-test.py` and `vm-orchestration-test.py` natively on the macOS guest
with synthetic state and fake commands. The pinned Linux container runs the Bash/zsh bootstrap suites
and always runs `vm-guest-test.py`, whose fake Homebrew, Colima, and Docker guest boundaries must never
execute natively on macOS. No checks are omitted; native execution of the two safe Python suites avoids
expensive process startup under x86 emulation. The default `scripts/check.sh` runs all suites inside
the isolated container.
Verification checks the
unauthenticated state, Bash/client tools, TUN device and home mount, GOST API and UI HTTP readiness,
and the single shell activation block. It finally runs the live macOS preference verifier twice via
its existing idempotence check. GOST API readiness also checks whether this Docker environment makes
the Linux host's loopback listener accessible from the macOS guest; failure is a real incompatibility,
not a simulated success. UI HTTP readiness does not prove browser rendering or API interaction.

The verifier uses an allowlisted temporary copy under the guest home, a synthetic GOST configuration,
an explicitly empty exported key, and a randomized Compose project. Before Docker workload use, it
rejects `DOCKER_HOST`, resolves and freezes `DOCKER_CONTEXT`, and accepts only an absolute local
Unix-socket endpoint. It clears caller Compose-file and environment-file overrides. It refuses
existing production container names, occupied management ports, or a pre-existing state volume for
its randomized project; rejected resources are not cleaned up because the verifier does not own them.
It removes only its own containers and state volume on exit. Cleanup failure retains the private
working directory, reports its location, returns nonzero, and suppresses terminal PASS. Docker's
built images and check image remain cached. Guest preferences and `.zshrc` remain modified. To stop
or remove the prepared Docker VM afterward:

```sh
colima stop --profile codyssey-verify
# Discard that profile's Linux disk and Docker cache when no longer needed:
colima delete --profile codyssey-verify
```

### Create a new macOS VM and run everything

On an Apple Silicon Mac running macOS 14 or newer, make Tart available through `mise`:

```sh
mise exec tart@2.40.1 -- tart --version
```

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
`mise exec tart@2.40.1 -- tart`; the repository-wide `mise.toml` is not changed to install Tart for
ordinary bootstrap users. The host needs no Docker engine or Docker CLI. Docker is installed and used
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
