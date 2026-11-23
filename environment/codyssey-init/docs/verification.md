# Verify the environment bootstrap

Run the maintenance examples from `environment/codyssey-init` unless noted. For Intel Fusion setup, use the [Intel reproduction guide](intel-macos-vm.md).

- [Run isolated tests](#safe-verification) for installer, shell, or settings changes.
- [Verify live preferences](#destructive-live-preference-verifier) and [type in the guest Terminal](#terminal-typing-check) on a disposable desktop.
- [Start a VM on Apple Silicon](#apple-silicon-with-tart) or [check an existing disposable guest](#an-existing-disposable-vm).

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

## Isolated Tailnet runtime lab

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

## Destructive live preference verifier

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
with `--list`, and preserves keyboard and text preferences. The combined VM service check
uses this mode and verifies live shortcut registration separately. The workstation-only
check uses the full preference verifier and may require Gureum approval.

## Terminal typing check

Open Terminal in the disposable VM desktop and run:

```sh
bash scripts/verify-macos-vm.sh --disposable --input-desktop
```

Choose Allow when prompted, then follow the typing prompts. The check requires Hangul composition,
Latin input after Control-Space, and Hangul composition after switching back. It checks the active
source in addition to the text typed into Terminal.
The [Intel Fusion workstation verification](intel-macos-vm.md#06-run-the-workstation-verification)
runs this typing check automatically over the clone's loopback console.
For a manual Fusion run, focus Terminal and wait for each prompt before entering
the next sample.

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
The VM driver checks the saved Dock pins and runs the launcher’s `--list` command.
To verify the Dock appearance and click behavior, open the retained VM console and
check that Terminal, Chrome, and the j launcher appear and open correctly.

On success, the requested setup remains applied and the temporary verifier snapshot is removed. On
any failure or interruption, restoration is attempted for every captured domain before the original
error is rethrown. If any domain cannot be restored, the private snapshot is retained and its path is
printed for manual recovery. Do not run the verifier on a workstation whose live preferences may not
be temporarily changed. The VM procedure in this guide exercises real preference changes and idempotence.
Failure restoration is covered by synthetic tests; authenticated tailnet login is outside its scope.

## Disposable macOS VMs

These scripts verify only this environment bootstrap. They use real Docker services and real macOS
preferences without an auth key. The normal bootstrap must remain in `NeedsLogin`; its authentication browser is disabled.
A separate browser check uses a fresh private profile and `about:blank`, and never completes external authentication. No coursework, remote tailnet access, or authenticated forwarding is
tested. The VM must be disposable: verification changes its user's `.zshrc`, Dock, keyboard settings,
and text preferences. The local lab authenticates synthetic nodes only to its own isolated Headscale server; it never logs into an external tailnet. Successful preference verification leaves the requested settings applied.

### Build a base with preinstalled applications

On Apple Silicon, install mise on the host. The host VM scripts use the opt-in
`mise.vm.toml` environment and install its pinned Tart 2.40.1 on macOS 14 or newer.
On Intel, prepare a Fusion Pro base as described under [Create a new macOS VM and run everything](intel-macos-vm.md).
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

The builder clones the source and changes only that new VM. It reuses a valid OrbStack bundle or
installs checksum-pinned OrbStack 2.2.4 in `~/Applications`, and ensures iTerm2 and Gureum are present. When absent, the builder
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
and shortcuts using the [macOS preference checks](workstation.md#verifying-shortcuts). In the final zsh,
check `mise` and `just`. If the test environment has an authorized Tailnet, check `just bash`,
`mise --version`, `zellij --version`, MagicDNS short names, and proxy toggling in `just browser`.
Rerun setup to verify reuse, then check that a graceful Tailnet container restart removes the
ephemeral identity and requires a fresh login.

### An existing disposable VM

For a workstation-only run, sign in to the guest and run the following from
`environment/codyssey-init` with Python 3.10+ and Chrome available. The setup
installs Node.js through mise when a compatible runtime is missing.

```sh
bash scripts/verify-macos-vm.sh --disposable --workstation
```

With Docker already running, Python 3.10+, Chrome, a logged-in desktop user, and ordinary macOS
preference domains present, run the combined workstation and service check inside the guest:

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
preparation using the [Fusion instructions](intel-macos-vm.md). Preparation starts a
dedicated `codyssey-verify` Colima profile using QEMU TCG. The Linux architecture is x86_64
inside an Apple Silicon macOS guest and aarch64 inside an Intel macOS guest. Cross-architecture
emulation avoids nested hardware virtualization.
The preparer defaults to ten minutes for Lima user-v2 address resolution on both
architectures because the emulated Linux guest can reach DHCP after Lima's usual
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
Verification checks the unauthenticated state, Bash/client tools, TUN device and home mount, the
local tunnel manager's HTTP readiness through GOST's Unix socket, absence of the legacy TCP control
endpoint, and a single shell activation block. It then runs the private local Headscale lab for
ephemeral lifecycle, short-name DNS and terminal tools, verifies a fresh portable browser profile
and relaunch, and verifies the real Dock launcher twice plus live shortcut registration. Input-method
approval and physical Hangul typing remain interactive checks. Run the full live preference verifier
separately in a logged-in disposable desktop session. HTTP readiness does not prove browser rendering
or forwarding; run the Linux browser check below for that.

### Linux tunnel UI and browser captures

From the checkout, with local Docker and Node.js 24 installed:

```sh
cd environment/codyssey-init
sh tests/tunnel-ui-check.sh
```

The check uses the Compose-pinned Linux GOST binary and pinned Playwright Chromium in a disposable
container with networking disabled except for its own loopback. A second GOST process provides the
real SOCKS5 endpoint, mapping a synthetic Tailscale IP to a loopback TCP service. The check does not
start or log into Tailscale. Review the screenshots in `tunnel-ui/test-artifacts/` (`desktop.png`,
`mobile.png`, `locked.png`, `empty.png`, and `error.png`). This is not macOS or live-tailnet verification.

### macOS verification isolation and cleanup

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

### Apple Silicon with Tart

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

## VM check scope and cleanup

Tart boots the clone headlessly. Fusion starts the clone through the Fusion app so the
running inventory and guest transport are available, and may show a first-start
notice in the console. Both backends retry the guest connection for six minutes.
On Fusion, the workstation check
has a twenty-minute timeout and the combined Aqua verification has a six-hour timeout.
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
forwarding on a real Mac. The full VM check requires successful provisioning, Docker and
bootstrap checks, desktop verification, and cleanup. The workstation-only check requires
successful desktop verification and cleanup.
