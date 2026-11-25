#!/bin/sh
set -eu

test -s /opt/vm/vmlinuz-virt || { echo "missing kernel" >&2; exit 1; }
test -s /opt/vm/initramfs.cpio.gz || { echo "missing initramfs" >&2; exit 1; }
exec timeout -s TERM -k 10 300 qemu-system-x86_64 \
  -machine pc,accel=tcg -cpu max -smp 1 -m 384M \
  -nodefaults -no-reboot -display none -serial stdio -monitor none \
  -kernel /opt/vm/vmlinuz-virt -initrd /opt/vm/initramfs.cpio.gz \
  -append 'console=ttyS0,115200 panic=-1 quiet' \
  -nic none
