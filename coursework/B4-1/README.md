# Isolated Linux Operations Lab

This self-contained project develops and verifies Bash monitoring/report scripts plus Linux
operational controls. Docker mode tests the scripts against an explicitly synthetic listener. QEMU
mode boots a separate x86_64 Alpine kernel under TCG and configures real guest accounts, ACLs,
OpenSSH, firewalld/nftables, cron, and log storage. It never requires KVM, privileged containers, a
host Docker socket, DIM access, or real credentials.

## Public verification

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

Docker mode checks healthy and unhealthy process/port paths, logging, firewall warnings, and summary
statistics. Its listener is a synthetic target and **is not evidence about any supplied application**.

VM mode uses 768 MiB RAM and one emulated CPU. Inside the guest it:

- listens with OpenSSH only on TCP 20022 and verifies effective `PermitRootLogin no`;
- activates firewalld with a drop target, no services, and only TCP 20022/15034 exceptions;
- creates admin/development/test users, common/core groups, setgid directories, and default ACLs;
- proves the test role can write shared uploads but cannot read protected key material;
- installs `monitor.sh` as the development role with core-group execution and mode 750;
- runs a non-root synthetic listener, performs resource logging, and generates a summary;
- registers the monitor in the admin role's crontab and waits for a genuine minute-boundary append.

The guest is an ephemeral initramfs rather than a persistent installed server. Because that root has
no block-device mount entry, the VM points disk collection at its writable `/tmp` tmpfs; Docker mode
exercises the normal `/` default. The SSH and application forwards bind only within the verification
container, QEMU user networking denies guest-initiated external connections, and no host port is
published.

## Monitoring scripts

`bin/monitor.sh` requires Bash and accepts configuration through environment variables. Defaults
target an application process name, TCP 15034, and `/var/log/agent-app/monitor.log`. A missing process
or listener exits nonzero. Firewall inactivity and CPU/memory/disk thresholds warn without failing.
Each sample has a timestamp, PID, and percentages. At 10 MiB the script rotates numbered files and
keeps at most ten prior logs. `bin/report.sh [LOG]` reports average/minimum/maximum values and sample
count, rejecting missing or malformed input.

## Private supplied-target boundary

The public build context never contains restricted archives or executables. An optional local-only
workflow accepts an explicitly provided ZIP path and ignored evidence directory:

```sh
sh scripts/verify-private.sh /absolute/path/to/input.zip /absolute/path/to/private/evidence/B4-1
```

That workflow builds a digest-pinned glibc guest, creates a stopped container, copies the untouched
archive into it with `docker cp`, and only then constructs an ephemeral initramfs inside the runtime.
The guest extracts one bounded x86 target into RAM, executes it as a non-root service user with a
40-second limit, checks its readiness/listener, and runs the public monitor. It does not unpack or
execute the input on the agent host, reverse engineer it, or copy it into an image. The raw serial log
is written only to the caller's ignored private evidence path.

See [the required operations report](docs/REPORT.md) and [review guide](docs/REVIEW.md).
