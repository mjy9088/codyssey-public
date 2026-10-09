FROM alpine@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412
RUN apk add --no-cache \
      bash=5.2.37-r0 \
      gawk=5.3.2-r2 \
      iproute2=6.15.0-r0 \
      netcat-openbsd=1.229.1-r0 \
      procps-ng=4.0.4-r3
WORKDIR /work
COPY bin/ bin/
COPY tests/ tests/
RUN chmod 0755 bin/*.sh tests/*.sh
ENTRYPOINT ["bash", "tests/run.sh"]
