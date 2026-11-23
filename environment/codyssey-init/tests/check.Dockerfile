FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
RUN apk add --no-cache \
      'bash~5' \
      coreutils \
      grep \
      'jq~1' \
      'nodejs~22' \
      util-linux-misc \
      'zsh~5'
WORKDIR /work
COPY Dockerfile docker-compose.yml init.sh next-script.zsh tailnet.sh justfile mise.toml mise.vm.toml README.md verify-macos-setup.py /src/
COPY lib/ /src/lib/
COPY tests/ /src/tests/
COPY scripts/ /src/scripts/
COPY sdk/ /src/sdk/
COPY macos-setup.sh /src/macos-setup.sh
COPY enable-korean.swift tailscale-entrypoint.sh /src/
COPY chrome-extension/ /src/chrome-extension/
COPY .env.example /src/.env.example
RUN mkdir -p /src/gost \
  && cp /src/tests/fixtures/gost.yaml /src/gost/gost.yaml \
  && cp /src/tests/fixtures/dockerignore /src/.dockerignore \
  && chmod 0755 /src/tests/*.sh /src/*.sh /src/lib/*.sh
ENTRYPOINT ["bash", "/src/tests/run.sh"]
