#!/usr/bin/env bash
set -euo pipefail
umask 077

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/browser-version.sh"
die() { printf 'tailnet-browser: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || die 'the portable browser launcher requires macOS.'
case $(uname -m) in
  x86_64) platform=mac-x64; checksum=$BROWSER_MAC_X64_SHA256 ;;
  arm64) platform=mac-arm64; checksum=$BROWSER_MAC_ARM64_SHA256 ;;
  *) die 'unsupported macOS architecture.' ;;
esac

prepare_only=0
if [[ ${1:-} == --prepare ]]; then prepare_only=1; shift; fi
for url in "$@"; do
  case $url in
    http://*|https://*|chrome://extensions/*|about:blank) ;;
    *) die 'arguments must be http(s) URLs, chrome://extensions/, or about:blank.' ;;
  esac
done

cache=${CODYSSEY_BROWSER_CACHE_DIR:-"$HOME/Library/Caches/codyssey-init"}
support=${CODYSSEY_BROWSER_SUPPORT_DIR:-"$HOME/Library/Application Support/codyssey-init"}
directory="$cache/chrome-$BROWSER_VERSION-$platform"
app="$directory/chrome-$platform/Google Chrome for Testing.app"
binary="$app/Contents/MacOS/Google Chrome for Testing"
profile="$support/tailnet-chrome-profile"
extension="$support/tailnet-chrome-extension"
staging=
cleanup() { [[ -z $staging ]] || rm -rf "$staging"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -x $binary ]]; then
  [[ ! -e $directory ]] || die "incomplete browser cache at $directory; move it aside before retrying."
  mkdir -p "$cache"
  staging=$(mktemp -d "$cache/.chrome-download.XXXXXX")
  printf 'Downloading Chrome for Testing %s (%s)…\n' "$BROWSER_VERSION" "$platform"
  curl --fail --location --silent --show-error --retry 3 \
    "https://storage.googleapis.com/chrome-for-testing-public/$BROWSER_VERSION/$platform/chrome-$platform.zip" \
    -o "$staging/browser.zip"
  actual=$(shasum -a 256 "$staging/browser.zip" | cut -d ' ' -f 1)
  [[ $actual == "$checksum" ]] || die 'browser archive checksum verification failed.'
  mkdir "$staging/unpacked"
  ditto -x -k "$staging/browser.zip" "$staging/unpacked"
  [[ -x "$staging/unpacked/chrome-$platform/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" ]] \
    || die 'download did not contain the expected browser executable.'
  mv "$staging/unpacked" "$directory"
  cleanup
  staging=
fi

mkdir -p "$profile" "$extension"
for file in manifest.json background.mjs proxy.mjs popup.html popup.css popup.mjs README.md; do
  install -m 0644 "$root/chrome-extension/$file" "$extension/$file"
done
# This is a private runtime copy. The ordinary unpacked extension stays opt-in.
printf '{"enableOnInstall":true}\n' >"$extension/startup.json"
printf 'Portable browser: %s\nProfile: %s\n' "$binary" "$profile"
if (( prepare_only )); then exit 0; fi
if (( $# == 0 )); then set -- 'http://localhost:18081/?api=http%3A%2F%2Flocalhost%3A18080'; fi
open -na "$app" --args \
  "--user-data-dir=$profile" "--load-extension=$extension" \
  --no-first-run --no-default-browser-check "$@"
