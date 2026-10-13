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

# codyssey-init: unpacked-extension-registry-v1
extensions=$extension
registry="$support/unpacked-extension-paths"
registered_extensions=("$extension")
if [[ -r $registry ]]; then
  while IFS= read -r registered || [[ -n $registered ]]; do
    if [[ -z $registered ]]; then
      printf 'tailnet-browser: ignoring empty extension registry entry.\n' >&2
      continue
    fi
    if [[ $registered != /* ]]; then
      printf 'tailnet-browser: ignoring non-absolute extension path: %s\n' "$registered" >&2
      continue
    fi
    if [[ $registered == *,* || $registered == *$'\r'* || $registered == *$'\n'* ]]; then
      printf 'tailnet-browser: ignoring extension path containing a separator: %s\n' "$registered" >&2
      continue
    fi
    if [[ ! -d $registered ]]; then
      printf 'tailnet-browser: ignoring stale extension path: %s\n' "$registered" >&2
      continue
    fi
    canonical=$(CDPATH= cd -- "$registered" && pwd -P)
    if [[ $canonical != "$registered" ]]; then
      printf 'tailnet-browser: ignoring non-canonical extension path: %s\n' "$registered" >&2
      continue
    fi
    if [[ ! -f $registered/manifest.json ]]; then
      printf 'tailnet-browser: ignoring extension without a regular manifest.json: %s\n' "$registered" >&2
      continue
    fi
    duplicate=0
    for accepted in "${registered_extensions[@]}"; do
      if [[ $accepted == "$registered" ]]; then duplicate=1; break; fi
    done
    if (( duplicate )); then
      printf 'tailnet-browser: ignoring duplicate extension path: %s\n' "$registered" >&2
      continue
    fi
    registered_extensions+=("$registered")
    extensions+=",$registered"
  done <"$registry"
elif [[ -e $registry || -L $registry ]]; then
  printf 'tailnet-browser: ignoring unreadable extension registry: %s\n' "$registry" >&2
fi

open -na "$app" --args \
  "--user-data-dir=$profile" "--load-extension=$extensions" \
  --no-first-run --no-default-browser-check "$@"
