# Bootstrap options and troubleshooting

Start with the [README](../README.md) for the install command.

## Availability and trusted source

The remote command downloads the latest public `main` branch. It buffers the bootstrap before
execution. Revision and mirror overrides are not supported; run `sh init.sh` from a reviewed local
checkout when a fixed revision is needed. `sh init.sh --help` works without network access.
The repository-root `init.sh` is the only supported public bootstrap entry point.
The old `install.sh` download wrapper has been removed. Implementation and maintenance
helpers such as `macos-setup.sh` and `enable-korean.swift` belong only in this directory,
not as independent copies at the monorepo root. The public `sh init.sh` commands run from the repository root.

Remote mode stages the complete reusable runtime, including `init.sh`, `verify-macos-setup.py`, and
runtime libraries, before copying anything into
`${CODYSSEY_INIT_DIR:-$HOME/.local/share/codyssey-init}`. It replaces a prior managed file only if
its SHA-256 matches a supported old release at the same path. A project-directory lock serializes
remote runs through activation. The installer stages every replacement beside its destination, then
rechecks all paths and Docker state before the first rename. Failed downloads, preparation failures,
and conflicts detected in preflight leave existing managed bytes untouched. Existing `.env` and
`gost/gost.yaml` files are preserved. A local checkout runs in place and rejects a different
`CODYSSEY_INIT_DIR`.

## Optional features

Run the same root `sh init.sh` command again whenever you want to choose features.
If you started with the remote one-line command, repeat that same command. The questions
are asked on every interactive run, even when an earlier run created `.env`, installed `j`,
or started services. No separate `tailnet.sh` command is needed to configure or retry setup.
Declining this time preserves earlier work; selecting Yes reuses or retries that feature.

Interactive prompts use `[y/N]`: only `y`, `Y`, `yes`, or `YES` opts in. These choices are
independent; a Tailnet failure does not suppress a separately selected `j` or macOS setup.
For unattended runs, set the [feature flags](../README.md#optional-features) to `1` or `0`.

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

## Repeated runs, diagnostics, and environment differences

Run `sh init.sh` again after correcting a failed prerequisite. Completed work is reused:
managed `j` is replaced atomically, shell activation blocks are written atomically and added once, existing `.env`
and GOST configuration are preserved. A running Tailscale process keeps its session; a restart
or recreation deliberately starts a new ephemeral identity.
See the [iTerm2 settings guide](workstation.md#iterm2) for app-specific recovery.

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
input, and browser behavior in your environment. Retry the relevant setup command after fixing the cause. OrbStack startup failure does not prevent a separately selected Dock launcher from being attempted.
Declining Dock cleanup adds the launcher only when `j` was explicitly selected. The launcher requires a working container when used.
Repeated runs cannot bypass system approval or make an incompatible Docker backend compatible.
Remote installations from accepted commit `a2838076abf01d03c02e672408adac51560a6c9b` can upgrade in
place by repeating the normal remote command. The upgrade checks the selected Docker engine without
starting it. If the legacy stack is still present, save pending changes and run `docker compose down`
with the old Compose file before retrying. The installer leaves that file in place and never stops
the legacy stack itself; see [Codyssey tunnels](tailnet.md#codyssey-tunnels).

If publication was interrupted, rerun the normal remote command to finish. The incomplete marker
blocks startup until all replacements are installed. Do not remove the marker or the lock file.
If a customized or unrecognized path is refused, back it up and review it, then restore its exact
supported original or move it aside before retrying. Do not move `.env` or `gost/gost.yaml`.

From a checkout containing the accepted Git object, run
`sh environment/codyssey-init/scripts/check.sh --remote-upgrade` to exercise the preflight,
interruption recovery, and overlapping invocations using disposable state.

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
