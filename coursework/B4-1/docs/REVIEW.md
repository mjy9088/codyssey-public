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

Private validation is optional for public reviewers because its input is intentionally absent. When
authorized locally, confirm the container is created before `docker cp`, the image build context is
only this public subtree, and the archive is added to an ephemeral initramfs at runtime. The guest
must bound extraction size, use the x86 target, run it as a non-root account, impose a timeout, require
five successful boot checks/readiness/port listening, and store serial output only below ignored
private evidence. Never publish that log or the supplied archive.

This lab demonstrates local emulated controls, not configuration of a classroom host, DIM, cloud
server, or production firewall. Runtime state disappears at guest shutdown.
