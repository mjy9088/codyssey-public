#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image="codyssey-init-check:local"
native_python=0
case ${1:-} in
  '') [ "$#" -eq 0 ] ;;
  --native-python)
    [ "$#" -eq 1 ]
    if [ "$(uname -s)" != Darwin ]; then
      printf '%s\n' '--native-python requires macOS; use the default container check on Linux.' >&2
      exit 1
    fi
    python3 -c 'import sys; assert sys.version_info >= (3, 10)'
    # Both suites use synthetic state and fake external commands only.
    python3 "$root/tests/macos-setup-test.py"
    python3 "$root/tests/vm-orchestration-test.py"
    native_python=1
    ;;
  *) printf 'Usage: sh scripts/check.sh [--native-python]\n' >&2; exit 1 ;;
esac
docker version >/dev/null
grep -qx '\*' "$root/.dockerignore"
grep -qx '!Dockerfile' "$root/.dockerignore"
tar -C "$root" -cf - \
  Dockerfile docker-compose.yml init.sh next-script.zsh tailnet.sh justfile mise.toml \
  README.md verify-macos-setup.py macos-setup.sh .env.example lib/auth.sh \
  tests/check.Dockerfile tests/run.sh tests/bootstrap-static.sh \
  tests/bootstrap-remote.sh tests/bootstrap-runtime.sh tests/fixtures/dockerignore \
  tests/macos-fake-tools.py tests/macos-setup-test.py tests/fixtures/gost.yaml \
  tests/vm-orchestration-test.py tests/vm-guest-test.py scripts/check.sh scripts/create-macos-vm.sh scripts/prepare-macos-vm.sh \
  scripts/verify-macos-vm.sh scripts/vm-files.sh | \
  docker build --file tests/check.Dockerfile --tag "$image" -
docker run --rm --network none --read-only \
  --tmpfs /tmp:rw,exec,size=64m,mode=1777 \
  --env CODYSSEY_NATIVE_PYTHON_CHECKS="$native_python" \
  --security-opt no-new-privileges --cap-drop ALL "$image"
