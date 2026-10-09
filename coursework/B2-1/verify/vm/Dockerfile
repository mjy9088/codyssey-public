ARG PYTHON_IMAGE=python@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

FROM ${PYTHON_IMAGE} AS initramfs-builder
ARG LINUX_VIRT_VERSION=6.12.112-r0
ARG LINUX_VIRT_SHA256=6694e66849759265135a930306452c944bf2159f259b8c8f1c8731e474f2830b
RUN apk add --no-cache ca-certificates=20250619-r0 cpio=2.15-r0 curl=8.14.1-r3 gzip=1.14-r2
WORKDIR /work
RUN curl --fail --location --proto '=https' --tlsv1.2 --output linux-virt.apk \
      "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/linux-virt-${LINUX_VIRT_VERSION}.apk" \
    && echo "${LINUX_VIRT_SHA256}  linux-virt.apk" | sha256sum -c - \
    && mkdir kernel root \
    && tar -xzf linux-virt.apk -C kernel \
    && cp kernel/boot/vmlinuz-virt /work/vmlinuz-virt \
    && cp -a /bin /sbin /lib /usr /etc root/ \
    && cp -a kernel/lib/modules root/lib/ \
    && mkdir -p root/app/budget_app root/app/tests root/dev root/proc root/sys root/tmp root/run root/www
COPY budget_app/ /work/root/app/budget_app/
COPY tests/ /work/root/app/tests/
COPY verify/vm/guest-init /work/root/init
RUN chmod 0755 root/init \
    && find root -exec touch -h -d '@0' {} + \
    && (cd root && find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) | gzip -n -9 > initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1
COPY --from=initramfs-builder /work/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /work/initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
EXPOSE 8080
HEALTHCHECK --interval=3s --timeout=2s --start-period=60s --retries=30 \
  CMD wget -q -T 1 -O - http://127.0.0.1:8080/result.json | grep -q '"status":"pass"'
ENTRYPOINT ["/usr/local/bin/launch-vm"]
