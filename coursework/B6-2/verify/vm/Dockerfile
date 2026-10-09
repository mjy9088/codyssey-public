ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

FROM ghcr.io/astral-sh/uv@sha256:9b0b40ee26d09b0ddb3b39f0aef24174f59f766af36591d541a2e14266a20886 AS uv-bin

FROM python@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844 AS guest-root
COPY --from=uv-bin /usr/local/bin/uv /usr/local/bin/uvx /bin/
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --locked --no-dev --no-install-project
COPY src/ src/
RUN uv sync --locked --no-dev && mkdir -p /app/data

FROM ${ALPINE_IMAGE} AS initramfs-builder
ARG ALPINE_RELEASE=3.22.6
ARG ALPINE_MINIROOTFS_SHA256=27694aaa55fd7a9e3ef596e0ad4eb66802308bb20172b17030cd5f4d8ae9bac2
ARG LINUX_VIRT_VERSION=6.12.112-r0
ARG LINUX_VIRT_SHA256=6694e66849759265135a930306452c944bf2159f259b8c8f1c8731e474f2830b
RUN apk add --no-cache ca-certificates=20260909-r0 cpio=2.15-r0 curl=8.14.1-r3 gzip=1.14-r2
WORKDIR /work
RUN curl --fail --location --proto '=https' --tlsv1.2 -o rootfs.tgz "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-${ALPINE_RELEASE}-x86_64.tar.gz" \
 && echo "${ALPINE_MINIROOTFS_SHA256}  rootfs.tgz" | sha256sum -c - \
 && curl --fail --location --proto '=https' --tlsv1.2 -o kernel.apk "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/linux-virt-${LINUX_VIRT_VERSION}.apk" \
 && echo "${LINUX_VIRT_SHA256}  kernel.apk" | sha256sum -c - \
 && mkdir root kernel && tar -xzf rootfs.tgz -C root && tar -xzf kernel.apk -C kernel \
 && cp kernel/boot/vmlinuz-virt . && cp -a kernel/lib/modules root/lib/
COPY --from=guest-root /usr/local/ /work/root/usr/local/
COPY --from=guest-root /lib/ /work/root/lib/
COPY --from=guest-root /usr/lib/ /work/root/usr/lib/
COPY --from=guest-root /app/ /work/root/app/
COPY verify/vm/guest-init /work/root/init
RUN chmod 0755 root/init && find root -exec touch -h -d '@0' {} + \
 && (cd root && find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) | gzip -n -9 > initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1
COPY --from=initramfs-builder /work/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /work/initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
EXPOSE 8000
HEALTHCHECK --interval=2s --timeout=2s --start-period=60s --retries=30 CMD wget -q -T 1 -O - http://127.0.0.1:8000/__vm-proof | grep -q '^kernel=Linux '
ENTRYPOINT ["/usr/local/bin/launch-vm"]
