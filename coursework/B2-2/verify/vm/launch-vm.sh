#!/bin/sh
set -eu
exec timeout 150 qemu-system-x86_64 -machine pc,accel=tcg -cpu max -smp 1 -m 512M \
  -nodefaults -no-reboot -display none -serial stdio -monitor none -nic none \
  -kernel /opt/vm/kernel -initrd /opt/vm/initramfs.gz -append 'console=ttyS0 panic=-1 quiet'
