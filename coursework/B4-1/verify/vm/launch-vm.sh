#!/bin/sh
set -eu
echo "VM-LAUNCH: x86_64 QEMU TCG, 768 MiB, isolated OS operations lab"
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
  -initrd /opt/vm/initramfs.cpio.gz \
  -append 'console=ttyS0,115200 panic=-1 quiet' \
  -device virtio-net-pci,netdev=guestnet \
  -netdev user,id=guestnet,restrict=on,hostfwd=tcp:127.0.0.1:20022-10.0.2.15:20022,hostfwd=tcp:127.0.0.1:15034-10.0.2.15:15034
