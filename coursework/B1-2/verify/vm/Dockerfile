ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
FROM node:22.19.0-bookworm-slim@sha256:4a4884e8a44826194dff92ba316264f392056cbe243dcc9fd3551e71cea02b90 AS site-builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY index.html tsconfig.json tsconfig.app.json tsconfig.node.json vite.config.ts ./
COPY src/ src/
RUN npm run build

FROM ${ALPINE_IMAGE} AS initramfs-builder
ARG ALPINE_RELEASE=3.22.6
ARG ALPINE_MINIROOTFS_SHA256=27694aaa55fd7a9e3ef596e0ad4eb66802308bb20172b17030cd5f4d8ae9bac2
ARG BUSYBOX_EXTRAS_VERSION=1.37.0-r20
ARG BUSYBOX_EXTRAS_SHA256=2b8e8919faa2fc7b52d36eebe2b42844d8a9e19e7e833de8e29883dd4eb0d6c1
ARG LINUX_VIRT_VERSION=6.12.112-r0
ARG LINUX_VIRT_SHA256=6694e66849759265135a930306452c944bf2159f259b8c8f1c8731e474f2830b
RUN apk add --no-cache ca-certificates=20260909-r0 cpio=2.15-r0 curl=8.14.1-r3 gzip=1.14-r2
WORKDIR /work
RUN curl --fail --location --proto '=https' --tlsv1.2 -o rootfs.tgz "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-${ALPINE_RELEASE}-x86_64.tar.gz" \
 && echo "${ALPINE_MINIROOTFS_SHA256}  rootfs.tgz" | sha256sum -c - \
 && curl --fail --location --proto '=https' --tlsv1.2 -o busybox.apk "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/busybox-extras-${BUSYBOX_EXTRAS_VERSION}.apk" \
 && echo "${BUSYBOX_EXTRAS_SHA256}  busybox.apk" | sha256sum -c - \
 && curl --fail --location --proto '=https' --tlsv1.2 -o kernel.apk "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/linux-virt-${LINUX_VIRT_VERSION}.apk" \
 && echo "${LINUX_VIRT_SHA256}  kernel.apk" | sha256sum -c - \
 && mkdir root kernel && tar -xzf rootfs.tgz -C root && tar -xzf busybox.apk -C root && tar -xzf kernel.apk -C kernel \
 && cp kernel/boot/vmlinuz-virt . && cp -a kernel/lib/modules root/lib/ && mkdir -p root/www
COPY verify/vm/guest-init /work/root/init
COPY verify/vm/httpd.conf /work/root/etc/httpd.conf
COPY --from=site-builder /app/dist/ /work/root/www/
RUN chmod 0755 root/init && find root -exec touch -h -d '@0' {} + \
 && (cd root && find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) | gzip -n -9 > initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1
COPY --from=initramfs-builder /work/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /work/initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
EXPOSE 8080
HEALTHCHECK --interval=2s --timeout=1s --start-period=45s --retries=20 CMD wget -q -T 1 -O - http://127.0.0.1:8080/__vm-proof.txt | grep -q '^kernel=Linux '
ENTRYPOINT ["/usr/local/bin/launch-vm"]
