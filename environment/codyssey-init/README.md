# Codyssey macOS tailnet bootstrap

This directory prepares a repeatable Tailscale and GOST environment for a macOS workstation that
already has a working Docker Engine and Compose v2. It builds a pinned Tailscale image with Bash and
other terminal tools, starts the tailnet and local GOST management services, and optionally applies a
small set of macOS preferences.

The bootstrap does not install Docker, authenticate to Tailscale by itself, or prove that a remote
tailnet is reachable. Those remain explicit user and environment boundaries. It can install a pinned,
checksum-verified `mise` binary when `mise` is missing.

## Availability and trusted source

Use a reviewed local checkout today:

```sh
cd environment/codyssey-init
bash init.sh
```

Do not use a mutable `main`/`master` raw URL. This work is not assumed to be present on GitHub's
current `main` branch. Remote installation is available only after the exact reviewed commit has been
published to an approved source. It requires both a base URL and a full 40-character commit. Download
the initial script completely before executing it; streaming `curl | bash` can execute a partial file:

```sh
export CODYSSEY_INIT_BASE_URL=https://raw.githubusercontent.com/OWNER/REPOSITORY
export CODYSSEY_INIT_REF=0123456789abcdef0123456789abcdef01234567
(
  installer=$(mktemp) || exit 1
  trap 'rm -f "$installer"' EXIT
  curl --fail --location --silent --show-error \
    "$CODYSSEY_INIT_BASE_URL/$CODYSSEY_INIT_REF/environment/codyssey-init/init.sh" \
    -o "$installer" && bash "$installer"
)
```

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
and launches `next-script.zsh` as an interactive zsh script with standard input attached to
`/dev/null`. Secret input is read directly and silently from `/dev/tty`.

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
`https://login.tailscale.com/...` authentication URL from Tailscale's output. It waits up to 60 seconds
for that URL because `NeedsLogin` can appear before the URL is logged, then fails with a command
to inspect the logs if no URL is available:

```sh
docker compose logs tailscale
```

It then waits for the local GOST UI and opens Chrome when available, falling back to the default
macOS browser. The URL is:

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
at `127.0.0.1:1055` and the GOST chain remain available alongside kernel networking; containerboot
passes that listener flag independently of the TUN mode. See the
[Tailscale Docker parameters](https://tailscale.com/docs/features/containers/docker/docker-params).

Tailscale state persists in the `tailscale-state` named volume. The GOST API listens only on
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
explicitly as the first argument). Arbitrary commands are never probed, prefixed, or rebuilt. The
named state volume is not removed.

## Optional macOS preferences

Preferences are opt-in and nonfatal to the bootstrap:

```sh
CODYSSEY_MACOS_SETUP=1 bash init.sh
```

`macos-setup.sh` refuses non-Darwin systems and never uses `sudo`. Before each independent preference
group, it creates a private per-run backup under
`~/Library/Application Support/codyssey-init/macos-backups/`. It then:

- disables macOS text automation;
- only when both Terminal and Google Chrome exist, replaces Dock app pins with those two apps,
  hides recent items, and removes folder stacks; otherwise the entire Dock group is left unchanged;
- preserves existing input sources while adding Korean 2-Set once;
- merges typed symbolic-hotkey entries 60 and 61 for Control-Space and Control-Shift-Space while
  preserving unrelated shortcuts; and
- restarts only the current user's Dock process.

It does not call private `activateSettings` APIs.

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
```

The bounded test build context excludes private `.env`, user-edited GOST runtime configuration,
caches, and unrelated artifacts; it injects a synthetic GOST fixture instead. Bootstrap tests cover
successful, failed, repeated, and conflicting immutable remote installs; preflight atomicity and
staging cleanup; verified missing-`mise` installation; exported-key and existing-`.env` precedence;
real-zsh execution; exact terminal-state restoration; browser-login URL handling; argument and exit
status preservation; and Bash-only rebuild scope. The same command also runs stateful macOS tests for
all preference groups, idempotence, private backups, confirmed absence versus export failure,
group-level rollback, interruption recovery, failed-rollback snapshot retention, app guards, and
current-user Dock restart behavior.
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

`docker compose down` preserves the named Tailscale state volume unless `--volumes` is explicitly
added.

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
the application image and bootstrap tool pins remain those in this repository.

Verification first runs `scripts/check.sh --native-python`, then runs the actual `init.sh` twice.
This mode runs both Python mock suites on the macOS guest with synthetic state and fake commands,
and retains the pinned Docker container for the Bash/zsh bootstrap suites. No checks are omitted;
using native guest Python avoids expensive process startup under x86 emulation. The default
`scripts/check.sh` still runs all suites inside the isolated container.
Verification checks the
unauthenticated state, Bash/client tools, TUN device and home mount, GOST API and UI HTTP readiness,
and the single shell activation block. It finally runs the live macOS preference verifier twice via
its existing idempotence check. GOST API readiness also checks whether this Docker environment makes
the Linux host's loopback listener accessible from the macOS guest; failure is a real incompatibility,
not a simulated success. UI HTTP readiness does not prove browser rendering or API interaction.

The verifier uses an allowlisted temporary copy under the guest home, a synthetic GOST configuration,
an explicitly empty exported key, and its own Compose project. It refuses existing production
container names or occupied management ports. It removes its own containers and state volume on exit;
cleanup failure retains the private working directory and reports its location. Docker's built images
and check image remain cached. Guest preferences and `.zshrc` remain modified. To stop or remove the
prepared Docker VM afterward:

```sh
colima stop --profile codyssey-verify
# Discard that profile's Linux disk and Docker cache when no longer needed:
colima delete --profile codyssey-verify
```

### Create a new macOS VM and run everything

On an Apple Silicon Mac running macOS 14 or newer, configure Tart through `mise`:

```sh
mise use tart@2.40.1
mise exec -- tart --version
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

All host Tart commands use `mise exec -- tart`; the host needs no Docker engine or Docker CLI.
Docker is installed and used only inside the disposable macOS guest for the environment tests.

After provisioning, cleanup shuts down Colima before stopping macOS so the nested Linux disk is
flushed. On completion or failure the new VM is stopped and retained for inspection. Pass
`--delete-on-success` to delete only this newly created VM after successful verification. Failed VMs
are always retained; Tart's downloaded base cache is retained too. The script prints commands to open
or delete its VM. Existing source VMs are never stopped or deleted.

Host orchestration tests require only Python and fake commands; they do not create VMs:

```sh
python3 tests/vm-orchestration-test.py
```

These orchestration tests do not establish a successful real VM run. Real guest success is reported
only when provisioning, Docker checks, both bootstrap passes, and live preference verification all
finish successfully.
