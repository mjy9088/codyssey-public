ARG PYTHON_IMAGE=python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

FROM ${PYTHON_IMAGE} AS initramfs-builder
RUN apk add --no-cache cpio
WORKDIR /rootfs
RUN mkdir -p app dev proc sys run tmp \
    && cp -a /bin /etc /lib /sbin /usr /rootfs/
COPY src/ /rootfs/app/src/
COPY tests/ /rootfs/app/tests/
COPY verify/vm/guest-init /rootfs/init
RUN chmod 0755 /rootfs/init \
    && find /rootfs -exec touch -h -d '@0' {} + \
    && (find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) \
      | gzip -n -9 > /initramfs.cpio.gz

FROM ${ALPINE_IMAGE} AS kernel-builder
RUN apk add --no-cache linux-virt

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64
COPY --from=kernel-builder /boot/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0644 /opt/vm/vmlinuz-virt && chmod 0755 /usr/local/bin/launch-vm
ENTRYPOINT ["/usr/local/bin/launch-vm"]
