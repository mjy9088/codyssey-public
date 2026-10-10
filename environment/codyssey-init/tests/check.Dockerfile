FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
RUN apk add --no-cache \
      bash=5.2.37-r0 \
      coreutils=9.7-r1 \
      grep=3.12-r0 \
      util-linux-misc=2.41.6-r1 \
      zsh=5.9-r5
WORKDIR /work
COPY Dockerfile docker-compose.yml init.sh next-script.zsh tailnet.sh justfile mise.toml README.md verify-macos-setup.py /src/
COPY lib/ /src/lib/
COPY tests/ /src/tests/
COPY scripts/ /src/scripts/
COPY macos-setup.sh /src/macos-setup.sh
COPY .env.example /src/.env.example
RUN mkdir -p /src/gost \
  && cp /src/tests/fixtures/gost.yaml /src/gost/gost.yaml \
  && cp /src/tests/fixtures/dockerignore /src/.dockerignore \
  && chmod 0755 /src/tests/*.sh /src/*.sh /src/lib/*.sh
ENTRYPOINT ["bash", "/src/tests/run.sh"]
