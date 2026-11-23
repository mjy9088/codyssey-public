ARG PYTHON_IMAGE=python@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

FROM ${PYTHON_IMAGE} AS initramfs-builder
RUN apk add --no-cache cpio gzip
WORKDIR /work
RUN apk fetch --no-cache --arch x86_64 linux-virt \
    && apk verify linux-virt-*.apk \
    && mkdir kernel root \
    && tar -xzf linux-virt-*.apk -C kernel boot/vmlinuz-virt \
    && cp kernel/boot/vmlinuz-virt /work/vmlinuz-virt \
    && cp -a /bin /sbin /lib /usr /etc root/ \
    && mkdir -p root/app/budget_app root/app/tests root/dev root/proc root/sys root/tmp
COPY budget_app/ /work/root/app/budget_app/
COPY tests/ /work/root/app/tests/
COPY verify/vm/guest-init /work/root/init
RUN chmod 0755 root/init \
    && find root -exec touch -h -d '@0' {} + \
    && (cd root && find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) | gzip -n -9 > initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64
COPY --from=initramfs-builder /work/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /work/initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
ENTRYPOINT ["/usr/local/bin/launch-vm"]
