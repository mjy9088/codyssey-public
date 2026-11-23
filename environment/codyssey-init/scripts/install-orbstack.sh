#!/usr/bin/env bash
# Install the app bundle in a disposable guest without starting OrbStack.
set -euo pipefail
umask 077
[[ $(uname -s) == Darwin && $(id -u) != 0 ]] || exit 1

check_app() {
  local app=$1 identifier binary
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") || return
  [[ $identifier == dev.kdrag0n.MacVirt || $identifier == dev.kdrag0n.OrbStack ]] || return
  for binary in bin/orb xbin/docker xbin/docker-compose xbin/docker-buildx; do
    [[ -f $app/Contents/MacOS/$binary && -x $app/Contents/MacOS/$binary ]] || return
  done
}

for app in /Applications/OrbStack.app "$HOME/Applications/OrbStack.app"; do
  if [[ -e $app || -L $app ]]; then
    check_app "$app" || { printf 'Invalid OrbStack bundle: %s\n' "$app" >&2; exit 1; }
    printf 'Reusing %s\n' "$app"
    exit 0
  fi
done

# Pinned OrbStack 2.2.4 checksums from Homebrew's official orbstack cask.
# https://github.com/Homebrew/homebrew-cask/blob/master/Casks/o/orbstack.rb
case $(uname -m) in
  arm64) arch=arm64; sha=f0c698e709c99fb3ee87f92c3a0445c6b8f5a10d6a0edd4f4d461925d194b86a ;;
  x86_64) arch=amd64; sha=b18b397aff7e81ab7d63934a569da659ec73b0a19a99fa7521d4b75c96db5544 ;;
  *) printf 'Unsupported OrbStack architecture.\n' >&2; exit 1 ;;
esac

stage=$(mktemp -d)
mount="$stage/mount"
mounted=0
copy=
cleanup() {
  status=$?
  trap - EXIT
  [[ -z $copy ]] || rm -rf -- "$copy"
  if (( mounted )) && ! hdiutil detach "$mount" -quiet; then
    printf 'Could not detach OrbStack disk image; staging retained at %s\n' "$stage" >&2
    (( status != 0 )) || status=1
  else
    rm -rf "$stage"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Downloading OrbStack 2.2.4.\n'
curl --fail --location --show-error --retry 3 \
  --proto '=https' --proto-redir '=https' \
  "https://cdn-updates.orbstack.dev/$arch/OrbStack_v2.2.4_21120_$arch.dmg" -o "$stage/orbstack.dmg"
[[ $(shasum -a 256 "$stage/orbstack.dmg" | cut -d ' ' -f 1) == "$sha" ]] || {
  printf 'OrbStack archive checksum mismatch.\n' >&2; exit 1;
}
mkdir -p "$mount" "$HOME/Applications"
hdiutil attach "$stage/orbstack.dmg" -mountpoint "$mount" -nobrowse -readonly -quiet
mounted=1
copy=$(mktemp -d "$HOME/Applications/.codyssey-orbstack.XXXXXX")
ditto "$mount/OrbStack.app" "$copy/OrbStack.app"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$copy/OrbStack.app/Contents/Info.plist") == 2.2.4 ]]
check_app "$copy/OrbStack.app"
[[ ! -e $HOME/Applications/OrbStack.app && ! -L $HOME/Applications/OrbStack.app ]]
mv -n "$copy/OrbStack.app" "$HOME/Applications/OrbStack.app"
[[ ! -e $copy/OrbStack.app ]]
printf 'Installed OrbStack 2.2.4 without launching it.\n'
