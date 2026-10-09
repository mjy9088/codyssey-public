ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
ARG PYTHON_IMAGE=python:3.13.7-slim-bookworm@sha256:adafcc17694d715c905b4c7bebd96907a1fd5cf183395f0ebc4d3428bd22d92d

FROM ${ALPINE_IMAGE} AS kernel-builder
RUN apk add --no-cache linux-virt=6.12.112-r0

FROM ${PYTHON_IMAGE} AS initramfs-builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      acl=2.3.1-3 \
      busybox-static=1:1.35.0-4+deb12u1+b1 \
      cpio=2.13+dfsg-7.1 \
      gzip=1.12-1 \
      iproute2=6.1.0-3 \
      procps=2:4.0.2-3 \
      unzip=6.0-28+deb12u1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /rootfs
RUN mkdir -p app dev proc sys run tmp mnt/private \
    && cp -a /bin /etc /lib /sbin /usr /var /rootfs/ \
    && if [ -d /lib64 ]; then cp -a /lib64 /rootfs/; fi
COPY --from=kernel-builder /boot/vmlinuz-virt /vmlinuz-virt
COPY --from=kernel-builder /lib/modules /rootfs/lib/modules
COPY bin/ /rootfs/lab/bin/
COPY verify/private/guest-init /rootfs/init
RUN chmod 0755 /rootfs/init /rootfs/lab/bin/*.sh \
    && find /rootfs -exec touch -h -d '@0' {} + \
    && (find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) \
      | gzip -n -9 > /initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1 \
    && mkdir /private-input
COPY --from=initramfs-builder /vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/private/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
ENTRYPOINT ["/usr/local/bin/launch-vm"]
