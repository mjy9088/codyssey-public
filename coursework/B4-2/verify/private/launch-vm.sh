#!/bin/sh
set -eu
test -s /private-input/input.zip || { echo 'PRIVATE-VM-BLOCKED: runtime input missing'; exit 1; }
case "${PRIVATE_RUN_ID:-}" in run.*) ;; *) echo 'PRIVATE-VM-BLOCKED: run identity missing'; exit 1 ;; esac
case "${PRIVATE_INPUT_SHA256:-}" in *[!0-9a-f]*|'') echo 'PRIVATE-VM-BLOCKED: input digest missing'; exit 1 ;; esac
test "${#PRIVATE_INPUT_SHA256}" -eq 64 || { echo 'PRIVATE-VM-BLOCKED: input digest invalid'; exit 1; }
actual_digest=$(sha256sum /private-input/input.zip)
actual_digest=${actual_digest%% *}
test "$actual_digest" = "$PRIVATE_INPUT_SHA256" || { echo 'PRIVATE-VM-BLOCKED: input digest mismatch'; exit 1; }
mkdir -p /tmp/overlay/root/private
cp /private-input/input.zip /tmp/overlay/root/private/input.zip
printf '%s\n' "$PRIVATE_RUN_ID" > /tmp/overlay/root/private/run-id
printf '%s\n' "$PRIVATE_INPUT_SHA256" > /tmp/overlay/root/private/input.sha256
(cd /tmp/overlay/root && find . -print | cpio -o -H newc 2>/dev/null) | gzip -n -9 > /tmp/overlay/input.cpio.gz
cat /opt/vm/initramfs.cpio.gz /tmp/overlay/input.cpio.gz > /tmp/overlay/combined.cpio.gz
echo 'PRIVATE-VM-LAUNCH: x86_64 QEMU TCG, one vCPU, 768 MiB, no network device'
exec qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu max \
  -smp 1 \
  -m 768M \
  -nodefaults \
  -no-reboot \
  -display none \
  -serial stdio \
  -monitor none \
  -kernel /opt/vm/vmlinuz-virt \
  -initrd /tmp/overlay/combined.cpio.gz \
  -append 'console=ttyS0,115200 panic=-1 quiet'
