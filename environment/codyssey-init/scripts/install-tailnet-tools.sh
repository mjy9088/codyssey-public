#!/usr/bin/env bash
# Build-time installation only; all release binaries are pinned and verified.
set -euo pipefail
version=v2026.10.5
case $(uname -m) in
  x86_64)
    platform=linux-x64-musl
    mise_sha=3e1ed8c0b2741469ca7482b8975fdfbd270bd4c18f3e478fc30cc042a65f63ac
    zellij_sha=d006c521dcb475a6005d741e9dd7c5758e5a23b28dd60a5c10cebfa4876319dd ;;
  aarch64)
    platform=linux-arm64-musl
    mise_sha=8815f6c50f553a5d9813c84af5093f6155d41ef0e7cab39c8b927217bfe65f2e
    zellij_sha=2a2c0621e6f3b11ecbb05d66939a48000a2508604620aa20727a5fd61c49f451 ;;
  *) printf 'Unsupported terminal image architecture.\n' >&2; exit 1 ;;
esac
download=$(mktemp)
trap 'rm -f "$download"' EXIT
curl --fail --location --silent --show-error \
  "https://github.com/jdx/mise/releases/download/$version/mise-$version-$platform" -o "$download"
printf '%s  %s\n' "$mise_sha" "$download" | sha256sum -c -
install -m 0755 "$download" /usr/local/bin/mise
mise use --global zellij@0.45.1
printf '%s  %s\n' "$zellij_sha" "$(mise which zellij)" | sha256sum -c -
mise --version
mise exec -- zellij --version
