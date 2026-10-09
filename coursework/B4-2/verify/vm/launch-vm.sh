#!/bin/sh
set -eu
echo 'VM-LAUNCH: x86_64 QEMU TCG, one vCPU, 512 MiB, no network device'
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
  -kernel /opt/vm/vmlinuz-virt \
  -initrd /opt/vm/initramfs.cpio.gz \
  -append 'console=ttyS0,115200 panic=-1 quiet'
