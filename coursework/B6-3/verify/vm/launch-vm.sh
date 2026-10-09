#!/bin/sh
set -eu
test -s /opt/vm/vmlinuz-virt
test -s /opt/vm/initramfs.cpio.gz
exec qemu-system-x86_64 -machine pc,accel=tcg -cpu max -smp 1 -m 512M -nodefaults \
  -no-reboot -display none -serial stdio -monitor none \
  -kernel /opt/vm/vmlinuz-virt -initrd /opt/vm/initramfs.cpio.gz \
  -append 'console=ttyS0,115200 panic=-1 quiet' \
  -device virtio-net-pci,netdev=guestnet \
  -netdev user,id=guestnet,restrict=on,hostfwd=tcp:0.0.0.0:8000-10.0.2.15:8000
