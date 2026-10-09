ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

FROM ${ALPINE_IMAGE} AS initramfs-builder

ARG ALPINE_RELEASE=3.22.6
ARG ALPINE_MINIROOTFS_SHA256=27694aaa55fd7a9e3ef596e0ad4eb66802308bb20172b17030cd5f4d8ae9bac2
ARG BUSYBOX_EXTRAS_VERSION=1.37.0-r20
ARG BUSYBOX_EXTRAS_SHA256=2b8e8919faa2fc7b52d36eebe2b42844d8a9e19e7e833de8e29883dd4eb0d6c1
ARG LINUX_VIRT_VERSION=6.12.112-r0
ARG LINUX_VIRT_SHA256=6694e66849759265135a930306452c944bf2159f259b8c8f1c8731e474f2830b

RUN apk add --no-cache \
      ca-certificates=20260909-r0 \
      cpio=2.15-r0 \
      curl=8.14.1-r3 \
      gzip=1.14-r2

WORKDIR /work

RUN curl --fail --location --proto '=https' --tlsv1.2 \
      --output minirootfs.tar.gz \
      "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-${ALPINE_RELEASE}-x86_64.tar.gz" \
    && echo "${ALPINE_MINIROOTFS_SHA256}  minirootfs.tar.gz" | sha256sum -c - \
    && curl --fail --location --proto '=https' --tlsv1.2 \
      --output busybox-extras.apk \
      "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/busybox-extras-${BUSYBOX_EXTRAS_VERSION}.apk" \
    && echo "${BUSYBOX_EXTRAS_SHA256}  busybox-extras.apk" | sha256sum -c - \
    && curl --fail --location --proto '=https' --tlsv1.2 \
      --output linux-virt.apk \
      "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/linux-virt-${LINUX_VIRT_VERSION}.apk" \
    && echo "${LINUX_VIRT_SHA256}  linux-virt.apk" | sha256sum -c - \
    && mkdir root kernel \
    && tar -xzf minirootfs.tar.gz -C root \
    && tar -xzf busybox-extras.apk -C root \
    && tar -xzf linux-virt.apk -C kernel \
    && cp kernel/boot/vmlinuz-virt /work/vmlinuz-virt \
    && cp -a kernel/lib/modules root/lib/

COPY verify/vm/guest-init /work/root/init
COPY web/ /work/root/www/

RUN test -s root/www/index.html \
    && chmod 0755 root/init \
    && find root -exec touch -h -d '@0' {} + \
    && (cd root && find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) \
      | gzip -n -9 > /work/initramfs.cpio.gz

FROM ${ALPINE_IMAGE}

RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1

COPY --from=initramfs-builder /work/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /work/initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm

RUN chmod 0755 /usr/local/bin/launch-vm \
    && test -s /opt/vm/vmlinuz-virt \
    && test -s /opt/vm/initramfs.cpio.gz

EXPOSE 8080

HEALTHCHECK --interval=2s --timeout=1s --start-period=45s --retries=15 \
  CMD wget -q -T 1 -O - http://127.0.0.1:8080/__vm-proof.txt | grep -q '^kernel=Linux '

ENTRYPOINT ["/usr/local/bin/launch-vm"]
