ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
FROM ${ALPINE_IMAGE} AS initramfs-builder
RUN apk add --no-cache \
      acl=2.3.2-r1 \
      bash=5.2.37-r0 \
      cpio=2.15-r0 \
      dcron=4.6-r0 \
      firewalld=2.3.0-r0 \
      gawk=5.3.2-r2 \
      iproute2=6.15.0-r0 \
      linux-virt=6.12.112-r0 \
      logrotate=3.21.0-r1 \
      netcat-openbsd=1.229.1-r0 \
      openssh-server=10.0_p1-r10 \
      procps-ng=4.0.4-r3
WORKDIR /rootfs
RUN mkdir -p app dev proc sys run tmp \
    && cp -a /bin /etc /lib /sbin /usr /var /rootfs/ \
    && cp /boot/vmlinuz-virt /vmlinuz-virt
COPY bin/ /rootfs/lab/bin/
COPY tests/synthetic-app.sh /rootfs/lab/synthetic-app.sh
COPY verify/vm/guest-init /rootfs/init
RUN chmod 0755 /rootfs/init /rootfs/lab/bin/*.sh /rootfs/lab/synthetic-app.sh \
    && find /rootfs -exec touch -h -d '@0' {} + \
    && (find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) \
      | gzip -n -9 > /initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1
COPY --from=initramfs-builder /vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
ENTRYPOINT ["/usr/local/bin/launch-vm"]
