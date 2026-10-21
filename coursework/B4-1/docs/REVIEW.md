# Review guide

## Script review

Run Docker verification and inspect `bin/monitor.sh` for fail-fast process/port checks, warning-only
thresholds, exact log fields, and bounded rotation. Confirm `report.sh` fails on no samples and reports
all three resources from valid input. The synthetic target announces itself explicitly.

## Guest review

Run VM verification and require all `VM-CHECK` lines plus both success markers. Inspect the guest
initialization script for effective SSH configuration, firewalld target/services/ports/interface,
role membership, positive and negative ACL checks, script ownership/mode, manual monitoring, crontab
installation, and a later log-line increase. QEMU must use TCG, one vCPU, bounded memory, restricted
user networking, no KVM, and no privileged mode.

## Private-input review

Private validation remains optional when its input is absent. When the canonical ignored archive is
present, confirm `scripts/verify.sh` selects it once and never falls back to synthetic results after a
failure. Confirm the container is created before `docker cp`, has no network plus explicit CPU,
memory, PID, tmpfs, and wall-clock bounds, the image build context is only this public subtree, and
the archive is added to an ephemeral initramfs at runtime. The guest
must bound extraction size, use the x86 target, run it as a non-root account, impose a timeout, require
five successful boot checks/readiness/port listening, and pass `AGENT_KEY_PATH` as the key
directory containing only `secret.key`. That synthetic key must contain one expected line and have
`agent-admin:agent-core` ownership with mode 640. Store serial output only below ignored private
evidence. Only the canonical `.local/B4-1/agent-app.zip` and `.local/evidence/B4-1` paths are allowed
inside the public checkout; other in-checkout paths and any path containing a symlink are rejected.
Never publish the logs or supplied archive.

This lab demonstrates local emulated controls, not configuration of a classroom host, DIM, cloud
server, or production firewall. Runtime state disappears at guest shutdown.
