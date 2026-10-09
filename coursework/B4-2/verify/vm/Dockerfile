ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
FROM ${ALPINE_IMAGE} AS fixture-builder
RUN apk add --no-cache gcc=14.2.0-r6 musl-dev=1.2.5-r12
COPY fixture/resource-fixture.c /src/resource-fixture.c
RUN gcc -std=c11 -O2 -Wall -Wextra -Werror -pthread -o /resource-fixture /src/resource-fixture.c

FROM ${ALPINE_IMAGE} AS initramfs-builder
RUN apk add --no-cache bash=5.2.37-r0 cpio=2.15-r0 linux-virt=6.12.112-r0 procps-ng=4.0.4-r3
WORKDIR /rootfs
RUN mkdir -p dev proc sys run tmp lab/bin lab/tests \
    && cp -a /bin /etc /lib /sbin /usr /var /rootfs/ \
    && cp /boot/vmlinuz-virt /vmlinuz-virt
COPY --from=fixture-builder /resource-fixture /rootfs/lab/bin/resource-fixture
COPY bin/monitor.sh /rootfs/lab/bin/monitor.sh
COPY bin/check-private-result.sh /rootfs/lab/bin/check-private-result.sh
COPY bin/supervise.sh /rootfs/lab/bin/supervise.sh
COPY tests/run.sh /rootfs/lab/tests/run.sh
COPY verify/vm/guest-init /rootfs/init
RUN chmod 0755 /rootfs/init /rootfs/lab/bin/* /rootfs/lab/tests/run.sh \
    && find /rootfs -exec touch -h -d '@0' {} + \
    && (find . -xdev -print0 | sort -z | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null) | gzip -n -9 > /initramfs.cpio.gz

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1
COPY --from=initramfs-builder /vmlinuz-virt /opt/vm/vmlinuz-virt
COPY --from=initramfs-builder /initramfs.cpio.gz /opt/vm/initramfs.cpio.gz
COPY verify/vm/launch-vm.sh /usr/local/bin/launch-vm
RUN chmod 0755 /usr/local/bin/launch-vm
ENTRYPOINT ["/usr/local/bin/launch-vm"]
