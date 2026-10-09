#!/bin/sh
set -eu

test -s /opt/vm/vmlinuz-virt || { printf 'Missing kernel\n' >&2; exit 1; }
test -s /opt/vm/initramfs.cpio.gz || { printf 'Missing initramfs\n' >&2; exit 1; }
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
  -kernel /opt/vm/vmlinuz-virt \
  -initrd /opt/vm/initramfs.cpio.gz \
  -append 'console=ttyS0,115200 panic=-1 quiet'
