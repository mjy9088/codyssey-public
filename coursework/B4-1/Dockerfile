FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
RUN apk add --no-cache \
      'bash~5' \
      gawk \
      iproute2 \
      netcat-openbsd \
      procps-ng
WORKDIR /work
COPY bin/ bin/
COPY scripts/verify.sh scripts/verify.sh
COPY tests/ tests/
COPY verify/private/guest-init verify/private/guest-init
RUN chmod 0755 bin/*.sh tests/*.sh
ENTRYPOINT ["bash", "tests/run.sh"]
