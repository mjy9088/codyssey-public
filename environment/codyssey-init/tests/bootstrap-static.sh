#!/usr/bin/env bash
set -euo pipefail
root=/src

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for file in Dockerfile docker-compose.yml init.sh next-script.zsh tailnet.sh justfile \
  mise.toml macos-setup.sh verify-macos-setup.py lib/auth.sh lib/preparation.sh \
  lib/readiness.zsh scripts/prepare-startup.sh tests/startup-overlap-test.sh \
  tests/preparation-safety-test.sh tests/auth-prompt-test.sh README.md; do
  [[ -f "$root/$file" ]] || fail "missing $file"
done

grep -Eq '^FROM tailscale/tailscale:[^ ]+@sha256:[0-9a-f]{64}$' "$root/Dockerfile"
grep -qx 'WORKDIR /host' "$root/Dockerfile"
for package in bash curl openssh-client-default git bind-tools; do
  grep -Eq "${package}=[^ \\\\]+" "$root/Dockerfile" || fail "unversioned $package"
done
grep -Eq 'TS_AUTHKEY:.*\$\{TS_AUTHKEY:-\}' "$root/docker-compose.yml"
grep -q 'TS_USERSPACE: "false"' "$root/docker-compose.yml"
grep -q '/dev/net/tun:/dev/net/tun' "$root/docker-compose.yml"
grep -Fq '${HOME}:/host:rw' "$root/docker-compose.yml"
grep -q 'just = "1\.43\.0"' "$root/mise.toml"
grep -q '^#!/usr/bin/env zsh$' "$root/next-script.zsh"
for file in next-script.zsh lib/readiness.zsh; do
  zsh -n "$root/$file"
done

if grep -Eq 'curl.+\|.+sh|mise\.run' "$root/init.sh"; then
  fail 'init uses a mutable shell installer'
fi
if grep -Eq '\{\{args\}\}' "$root/justfile"; then
  fail 'justfile interpolates arbitrary arguments into a shell recipe'
fi

for file in tailscale-entrypoint.sh init.sh lib/auth.sh lib/preparation.sh \
  scripts/prepare-startup.sh tests/startup-overlap-test.sh tests/preparation-safety-test.sh tests/auth-prompt-test.sh; do
  bash -n "$root/$file"
done
sh -n "$root/install.sh"
grep -q -- 'tailscaled.state' "$root/tailscale-entrypoint.sh"
grep -q 'tailscale-state:/var/lib/tailscale' "$root/docker-compose.yml"
grep -q '100.100.100.100' "$root/scripts/tailnet-dns.sh"
grep -q 'codyssey-tailscale' "$root/Dockerfile"
