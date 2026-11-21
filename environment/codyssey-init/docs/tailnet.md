# Tailnet services and terminal

Select Tailnet in the [bootstrap](../README.md). Run maintenance commands from the installed or checked-out `environment/codyssey-init` directory.

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
be installed; the bootstrap does not download it. OrbStack windows remain under the user's control. The CLI is documented in
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

Startup prints a single preparation message and the environment URL. Docker builds run privately;
service startup and terminal image upgrades are quiet on success. Failures include the last twelve
log lines and preserve the command's exit status. Temporary logs are removed after use.

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
