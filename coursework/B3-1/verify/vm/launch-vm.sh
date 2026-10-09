#!/bin/sh
set -eu

kernel=/opt/vm/vmlinuz-virt
initramfs=/opt/vm/initramfs.cpio.gz

test -s "$kernel" || { echo "VM-LAUNCH-FATAL: missing $kernel" >&2; exit 1; }
test -s "$initramfs" || { echo "VM-LAUNCH-FATAL: missing $initramfs" >&2; exit 1; }

echo "VM-LAUNCH: qemu-system-x86_64 TCG, guest memory 256 MiB, HTTP forward 0.0.0.0:8080"
exec qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu max \
  -smp 1 \
  -m 256M \
  -nodefaults \
  -no-reboot \
  -display none \
  -serial stdio \
  -monitor none \
  -kernel "$kernel" \
  -initrd "$initramfs" \
  -append 'console=ttyS0,115200 panic=-1 quiet' \
  -device virtio-net-pci,netdev=guestnet \
  -netdev user,id=guestnet,restrict=on,hostfwd=tcp:0.0.0.0:8080-10.0.2.15:8080
