ARG ALPINE_IMAGE=alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
FROM ${ALPINE_IMAGE} AS guest
RUN apk add --no-cache ca-certificates=20260909-r0 curl=8.14.1-r3 cpio=2.15-r0 gzip=1.14-r2
WORKDIR /work
RUN curl -fSL --proto '=https' -o root.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.6-x86_64.tar.gz \
    && echo '27694aaa55fd7a9e3ef596e0ad4eb66802308bb20172b17030cd5f4d8ae9bac2  root.tar.gz' | sha256sum -c - \
    && curl -fSL --proto '=https' -o kernel.apk https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/linux-virt-6.12.112-r0.apk \
    && echo '6694e66849759265135a930306452c944bf2159f259b8c8f1c8731e474f2830b  kernel.apk' | sha256sum -c - \
    && mkdir root kernel && tar -xzf root.tar.gz -C root && tar -xzf kernel.apk -C kernel \
    && cp -a kernel/lib/modules root/lib/ \
    && apk --root /work/root --arch x86_64 --initdb --no-scripts --keys-dir /etc/apk/keys \
       --repositories-file /etc/apk/repositories add --no-cache git=2.49.1-r0 bash=5.2.37-r0 nodejs=22.23.2-r0
COPY src/ /work/root/app/src/
COPY tests/ /work/root/app/tests/
COPY verify/check.sh /work/root/app/verify/check.sh
COPY verify/vm/guest-init /work/root/init
RUN chmod 0755 root/init && find root -exec touch -h -d '@0' {} + \
    && (cd root && find . -print0 | sort -z | cpio --null -o -H newc --owner=0:0 --reproducible 2>/dev/null) | gzip -n -9 > initramfs.gz
FROM ${ALPINE_IMAGE}
RUN apk add --no-cache qemu-system-x86_64=10.0.0-r1
COPY --from=guest /work/kernel/boot/vmlinuz-virt /opt/vm/kernel
COPY --from=guest /work/initramfs.gz /opt/vm/initramfs.gz
COPY verify/vm/launch-vm.sh /opt/vm/launch-vm.sh
RUN chmod a+r /opt/vm/*
ENTRYPOINT ["sh", "/opt/vm/launch-vm.sh"]
