#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image="codyssey-init-check:local"
docker version >/dev/null
grep -qx '\*' "$root/.dockerignore"
grep -qx '!Dockerfile' "$root/.dockerignore"
tar -C "$root" -cf - \
  Dockerfile docker-compose.yml init.sh next-script.zsh tailnet.sh justfile mise.toml \
  README.md verify-macos-setup.py macos-setup.sh .env.example lib/auth.sh \
  tests/check.Dockerfile tests/run.sh tests/bootstrap-static.sh \
  tests/bootstrap-remote.sh tests/bootstrap-runtime.sh tests/fixtures/dockerignore \
  tests/macos-fake-tools.py tests/macos-setup-test.py tests/fixtures/gost.yaml | \
  docker build --file tests/check.Dockerfile --tag "$image" -
docker run --rm --network none --read-only \
  --tmpfs /tmp:rw,exec,size=64m,mode=1777 \
  --security-opt no-new-privileges --cap-drop ALL "$image"
