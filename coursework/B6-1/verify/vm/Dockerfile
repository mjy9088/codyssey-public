ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

FROM ${ALPINE_IMAGE} AS runtime-root
RUN apk add --no-cache 'sqlite~3'
WORKDIR /app
COPY README.md README.md
COPY sql/ sql/
COPY results/ results/
COPY scripts/check.sh scripts/check.sh
RUN chmod 0755 scripts/check.sh

FROM ${ALPINE_IMAGE} AS initramfs-builder
RUN apk add --no-cache cpio gzip
WORKDIR /work
RUN apk fetch --no-cache --arch x86_64 linux-virt \
    && apk verify linux-virt-*.apk \
    && mkdir kernel root \
    && tar -xzf linux-virt-*.apk -C kernel \
    && cp kernel/boot/vmlinuz-virt /work/vmlinuz-virt
COPY --from=runtime-root / /work/root/
COPY verify/vm/guest-init /work/root/init
RUN cp -a kernel/lib/modules root/lib/ \
    && chmod 0755 root/init \
    && find root -exec touch -h -d '@0' {} + \
    && (cd root && find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) \
      | gzip -n -9 > /work/initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64
COPY --from=initramfs-builder /work/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /work/initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
ENTRYPOINT ["/usr/local/bin/launch-vm"]
