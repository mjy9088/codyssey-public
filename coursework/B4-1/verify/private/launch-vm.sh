#!/bin/sh
set -eu
test -s /private-input/input.zip || { echo 'PRIVATE-VM-FAILURE: input archive missing'; exit 1; }
mkdir -p /tmp/private-overlay/root/private
cp /private-input/input.zip /tmp/private-overlay/root/private/input.zip
(cd /tmp/private-overlay/root && find . -print | cpio -o -H newc 2>/dev/null) | gzip -n -9 > /tmp/private-overlay/input.cpio.gz
cat /opt/vm/initramfs.cpio.gz /tmp/private-overlay/input.cpio.gz > /tmp/private-overlay/combined.cpio.gz
echo 'PRIVATE-VM-LAUNCH: x86_64 QEMU TCG, 1024 MiB, ephemeral initramfs input'
exec qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu max \
  -smp 1 \
  -m 1024M \
  -nodefaults \
  -no-reboot \
  -display none \
  -serial stdio \
  -monitor none \
  -kernel /opt/vm/vmlinuz-virt \
  -initrd /tmp/private-overlay/combined.cpio.gz \
  -append 'console=ttyS0,115200 panic=-1 quiet'
