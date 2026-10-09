ARG PYTHON_IMAGE=python@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
ARG UV_IMAGE=ghcr.io/astral-sh/uv@sha256:e4644cb5bd56fdc2c5ea3ee0525d9d21eed1603bccd6a21f887a938be7e85be1
ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412

FROM ${UV_IMAGE} AS uv
FROM ${PYTHON_IMAGE} AS runtime-root
ENV UV_LINK_MODE=copy
WORKDIR /app
COPY --from=uv /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project
COPY mini_git/ mini_git/
COPY verify/guest_check.py verify/guest_check.py
COPY main.py ./

FROM ${ALPINE_IMAGE} AS initramfs-builder
ARG LINUX_VIRT_VERSION=6.12.112-r0
ARG LINUX_VIRT_SHA256=6694e66849759265135a930306452c944bf2159f259b8c8f1c8731e474f2830b
RUN apk add --no-cache \
      ca-certificates=20260909-r0 \
      cpio=2.15-r0 \
      curl=8.14.1-r3 \
      gzip=1.14-r2
WORKDIR /work
RUN curl --fail --location --proto '=https' --tlsv1.2 \
      --output linux-virt.apk \
      "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/linux-virt-${LINUX_VIRT_VERSION}.apk" \
    && echo "${LINUX_VIRT_SHA256}  linux-virt.apk" | sha256sum -c - \
    && mkdir kernel root \
    && tar -xzf linux-virt.apk -C kernel \
    && cp kernel/boot/vmlinuz-virt /work/vmlinuz-virt
COPY --from=runtime-root / /work/root/
COPY verify/vm/guest-init /work/root/init
RUN cp -a kernel/lib/modules root/lib/ \
    && chmod 0755 root/init \
    && find root -exec touch -h -d '@0' {} + \
    && (cd root && find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) \
      | gzip -n -9 > /work/initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1
COPY --from=initramfs-builder /work/vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /work/initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
ENTRYPOINT ["/usr/local/bin/launch-vm"]
