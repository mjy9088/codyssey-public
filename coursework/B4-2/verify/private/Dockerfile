ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
ARG DEBIAN_IMAGE=debian:bookworm-slim@sha256:df52e55e3361a81ac1bead266f3373ee55d29aa50cf0975d440c2be3483d8ed3

FROM ${ALPINE_IMAGE} AS kernel-builder
RUN apk add --no-cache linux-virt=6.12.112-r0

FROM ${DEBIAN_IMAGE} AS initramfs-builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      busybox-static=1:1.35.0-4+deb12u1+b1 \
      cpio=2.13+dfsg-7.1 \
      coreutils=9.1-1 \
      gzip=1.12-1 \
      procps=2:4.0.2-3 \
      unzip=6.0-28+deb12u1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /rootfs
RUN mkdir -p dev proc sys run tmp private \
    && cp -a /bin /etc /lib /sbin /usr /var /rootfs/ \
    && if test -d /lib64; then cp -a /lib64 /rootfs/; fi
COPY --from=kernel-builder /boot/vmlinuz-virt /vmlinuz-virt
COPY --from=kernel-builder /lib/modules /rootfs/lib/modules
COPY bin/monitor.sh /rootfs/lab/bin/monitor.sh
COPY bin/supervise.sh /rootfs/lab/bin/supervise.sh
COPY verify/private/guest-init /rootfs/init
RUN chmod 0755 /rootfs/init /rootfs/lab/bin/monitor.sh /rootfs/lab/bin/supervise.sh \
    && find /rootfs -exec touch -h -d '@0' {} + \
    && (find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) | gzip -n -9 > /initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1 cpio=2.15-r0 \
    && mkdir /private-input
COPY --from=initramfs-builder /vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/private/launch-vm.sh /usr/local/bin/launch-private-vm
RUN chmod 0755 /usr/local/bin/launch-private-vm
ENTRYPOINT ["/usr/local/bin/launch-private-vm"]
