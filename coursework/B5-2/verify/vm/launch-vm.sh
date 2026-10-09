#!/bin/sh
set -eu

kernel=/opt/vm/vmlinuz-virt
initramfs=/opt/vm/initramfs.cpio.gz
test -s "$kernel" || { printf 'Missing kernel\n' >&2; exit 1; }
test -s "$initramfs" || { printf 'Missing initramfs\n' >&2; exit 1; }

exec qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu max \
  -smp 1 \
  -m 512M \
  -nodefaults \
  -no-reboot \
  -display none \
  -serial stdio \
  -monitor none \
  -kernel "$kernel" \
  -initrd "$initramfs" \
  -append 'console=ttyS0,115200 panic=-1 quiet'
