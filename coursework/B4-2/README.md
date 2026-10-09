# Bounded OS Resource Observation Lab

This standalone lab observes three OS-visible failure patterns against an explicitly synthetic
program: growing resident memory followed by an application policy exit, sustained process-local CPU
followed by a watchdog signal, and a two-thread/two-lock deadlock. It runs the same assertions in a
restricted Docker container and in a real x86_64 Linux guest under QEMU TCG.

The synthetic program is a diagnostic fixture. Its behavior and the three public reports **are not
findings about any supplied program**. Restricted-input output is kept only in ignored private
evidence, and the reports state which supplied-program requirements remain unobserved.

## Verify

Requirements: Docker Engine with Compose v2. No KVM, privileged mode, host socket inside the
workload, external credentials, or host network changes are used.
Both Compose services set `network_mode: none`.

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

Docker mode is read-only, drops every capability, requests one CPU and 256 MiB through Docker, and
uses only a bounded tmpfs. Host cgroup support determines whether those outer CPU/memory requests are
enforced. VM mode builds an ephemeral initramfs and explicitly boots with one emulated CPU and 512 MiB
RAM, has no emulated network device, and powers off after the checks. The verification wrapper limits
the Docker workload to 60 seconds and the QEMU workload to 120 seconds, then removes the Compose
project on success, failure, or timeout. Both modes test:

| Case | Before | After/control | Required observation |
| --- | --- | --- | --- |
| Memory | `MEMORY_LIMIT=50` | `MEMORY_LIMIT=80` | RSS rises; both are application exits; the higher limit survives longer |
| CPU | `CPU_MAX_OCCUPY=25` | `CPU_MAX_OCCUPY=100` | target CPU rises; low threshold gets watchdog SIGTERM; control completes |
| Deadlock | `MULTI_THREAD_ENABLE=true` | `false` | PID and blocked threads persist only in the enabled run; control completes |

Direct harness runs create a unique `run.XXXXXX` directory below
`${LAB_OUTPUT_DIR:-/tmp/b4-2-artifacts}` and print its path. The harness never recursively clears the
caller-selected base directory. Compose's disposable runs keep output in tmpfs. Generated logs are
not tracked because they become stale, duplicate rerunnable automation, increase repository size,
and can disclose runtime details. The three Markdown reports are tracked because they are explicit
submission deliverables; they describe durable, asserted observations rather than embedding generated
raw logs.

## Monitor output

`bin/monitor.sh PID LOG [COUNT [INTERVAL]]` samples only the named process. It parses start time only
after the closing parenthesis in `/proc/PID/stat`, so spaces or `)` in the process name do not shift
fields. Each line includes a UTC timestamp, kernel uptime, PID, process CPU percentage, RSS in KiB,
process state, and thread count. `ps %CPU` is a lifetime average, not an instantaneous CPU sample.
`/proc/uptime` refers to the Docker host kernel in container mode and the guest kernel under QEMU. The
synthetic deadlock test requires the same thread IDs, bounded RSS variation, an unchanged final log,
and a live process across the sample window; a live PID alone is never treated as proof of deadlock.

## Optional restricted-input observation

Authorized local users may run:

```sh
sh scripts/observe-private.sh /absolute/path/to/input.zip /absolute/path/to/private/evidence/B4-2
```

The image is built only from this public subtree. The stopped container receives the untouched ZIP
at runtime with `docker cp`; extraction and execution occur only in a no-network QEMU TCG guest. The
evidence argument is an external root; each invocation creates a fresh mode-0700 `run.XXXXXX`
directory and refuses symlinked inputs/evidence roots or canonical paths inside the public checkout.
The guest uses a dedicated non-root account, one vCPU, 768 MiB guest RAM, requested outer 1 GiB/one-CPU
container limits, bounded extraction, and per-run plus overall wall-clock timeouts. Outer cgroup limit
enforcement depends on the Docker host; QEMU's guest RAM and vCPU bounds remain explicit. The observer
runs independent memory, CPU, and threading pairs. Every sample records all service-account processes,
their parent relationship, every thread, aggregate CPU/RSS, and per-PID `monitor.sh` output where the
process remains available. It gathers ordinary application logs and `/proc`/`ps` metrics only. It does
not decompile, trace, inspect binary contents, or place the archive in an image. The target executable
and parent are root-owned and non-writable; each case receives fresh service-owned home/log state while
root-only capture remains separate. Application lines are prefixed before entering the control stream,
and each case requires zero surviving service-account processes after cleanup. Raw serial output is
restricted evidence and must never be published. The wrapper applies `umask 077`, saves Docker's raw
stdout/stderr before any transformation, records the timeout/docker exit status directly, and creates
a CR-normalized local copy. Success requires status zero, exactly one completion marker, all six
case-end markers, and no blocked/failure marker; `COMPLETE` alone is insufficient.

The public VM image compiles the fixture in a separate stage and omits compiler packages from the
initramfs. This replaced the earlier 99,943,376-byte compressed initramfs that triggered an early
unpack write error under the 512 MiB guest bound. The corrected image measured 33,911,770 bytes and
booted under the same bound without that error.

See [`reports/`](reports/) for the issue-style reports and [`docs/REVIEW.md`](docs/REVIEW.md) for the
evidence boundary and review checklist.
