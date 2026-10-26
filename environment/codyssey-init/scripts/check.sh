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
    # These suites use synthetic state and fake external commands only.
    python3 "$root/tests/portable-browser-test.py"
    python3 "$root/tests/macos-setup-test.py"
    python3 "$root/tests/vm-orchestration-test.py"
    python3 "$root/tests/preinstalled-tools-test.py"
    native_python=1
    ;;
  *) printf 'Usage: sh scripts/check.sh [--native-python]\n' >&2; exit 1 ;;
esac
docker version >/dev/null
grep -qx '\*' "$root/.dockerignore"
grep -qx '!Dockerfile' "$root/.dockerignore"
context=$(mktemp -d)
trap 'rm -rf "$context"' EXIT HUP INT TERM
tar -C "$root" -cf "$context/payload.tar" \
  Dockerfile docker-compose.yml init.sh next-script.zsh tailnet.sh justfile mise.toml mise.vm.toml \
  README.md HANDOFF.md verify-macos-setup.py macos-setup.sh enable-korean.swift tailscale-entrypoint.sh .env.example \
  lib/auth.sh lib/preparation.sh lib/readiness.zsh lib/bootstrap-tools.sh \
  tests/check.Dockerfile tests/run.sh tests/bootstrap-static.sh \
  tests/bootstrap-remote.sh tests/bootstrap-runtime.sh tests/managed-j-runtime.sh tests/startup-overlap-test.sh \
  tests/preparation-safety-test.sh tests/auth-prompt-test.sh tests/fixtures/dockerignore \
  tests/macos-fake-tools.py tests/macos-setup-test.py tests/fixtures/gost.yaml \
  tests/vm-orchestration-test.py tests/vm-guest-test.py tests/preinstalled-tools-test.py scripts/check.sh scripts/create-macos-vm.sh scripts/prepare-macos-vm.sh \
  scripts/verify-macos-vm.sh scripts/install-preinstalled-apps.sh scripts/create-preinstalled-macos-image.sh scripts/check-preinstalled-apps.py scripts/verify-portable-browser.py scripts/vm-files.sh \
  chrome-extension/manifest.json chrome-extension/background.mjs chrome-extension/proxy.mjs \
  chrome-extension/popup.html chrome-extension/popup.css chrome-extension/popup.mjs \
  chrome-extension/README.md chrome-extension/startup.json scripts/install-chrome-extension.sh tests/chrome-extension-test.mjs \
  scripts/tailnet-browser.sh scripts/browser-version.sh scripts/install-gureum.sh tests/portable-browser-test.py \
  scripts/configure-tailnet-browser.py \
  scripts/install-tailnet-tools.sh scripts/tailnet-dns.sh scripts/prepare-startup.sh scripts/quiet-desktop.swift scripts/verify-tailnet-runtime.py \
  tests/tailnet-dns-test.sh
tar -C "$context" -xf "$context/payload.tar"
rm "$context/payload.tar"
printf 'Preparing isolated checks…\n'
if docker build --file "$context/tests/check.Dockerfile" --tag "$image" "$context" >"$context/build.log" 2>&1; then
  :
else
  result=$?
  printf 'Check image build failed (exit %s).\n' "$result" >&2
  tail -n 12 "$context/build.log" >&2
  exit "$result"
fi
docker run --rm --network none --read-only \
  --tmpfs /tmp:rw,exec,size=64m,mode=1777 \
  --env CODYSSEY_NATIVE_PYTHON_CHECKS="$native_python" \
  --security-opt no-new-privileges --cap-drop ALL "$image"
