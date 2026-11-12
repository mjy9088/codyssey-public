#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $(uname -s) == Darwin ]] || { printf 'Ghostty setup requires macOS.\n' >&2; exit 1; }
# Official universal macOS binary; pin from Homebrew's reviewed cask:
# https://github.com/Homebrew/homebrew-cask/blob/main/Casks/g/ghostty.rb
version=1.4.0
checksum=3a02075dbd24318d778426af41dee5507d53ecc4578ede96912ec9ce6d18d3e8
plistbuddy_bin=${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}
for app in "${CODYSSEY_APPLICATIONS_DIR:-/Applications}/Ghostty.app" "$HOME/Applications/Ghostty.app"; do
  if [[ -d $app ]]; then
    [[ $("$plistbuddy_bin" -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == com.mitchellh.ghostty ]]
    [[ -x $app/Contents/MacOS/ghostty ]]
    printf 'Reusing %s\n' "$app"
    exit 0
  fi
done
stage=$(mktemp -d)
mount="$stage/mount"
mounted=0
copy=
cleanup() {
  result=$?
  trap - EXIT
  [[ -z $copy ]] || rm -rf "$copy"
  if (( mounted )) && ! hdiutil detach "$mount" -quiet; then
    printf 'Could not detach Ghostty image; staging retained at %s\n' "$stage" >&2
    (( result != 0 )) || result=1
  else
    rm -rf "$stage"
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
curl --fail --location --silent --show-error --retry 3 \
  "https://release.files.ghostty.org/$version/Ghostty.dmg" -o "$stage/Ghostty.dmg"
[[ $(shasum -a 256 "$stage/Ghostty.dmg" | cut -d ' ' -f 1) == "$checksum" ]] || {
  printf 'Ghostty checksum verification failed.\n' >&2; exit 1;
}
mkdir "$mount"
hdiutil attach "$stage/Ghostty.dmg" -mountpoint "$mount" -nobrowse -readonly -quiet
mounted=1
[[ $("$plistbuddy_bin" -c 'Print :CFBundleIdentifier' "$mount/Ghostty.app/Contents/Info.plist") == com.mitchellh.ghostty ]]
[[ $("$plistbuddy_bin" -c 'Print :CFBundleShortVersionString' "$mount/Ghostty.app/Contents/Info.plist") == "$version" ]]
mkdir -p "$HOME/Applications"
# Stage the entire bundle on the destination filesystem. Interrupted copies never
# leave an apparently installed app, and the next run can retry safely.
copy=$(mktemp -d "$HOME/Applications/.codyssey-ghostty.XXXXXX")
if ditto "$mount/Ghostty.app" "$copy/Ghostty.app" && [[ -x $copy/Ghostty.app/Contents/MacOS/ghostty ]] && [[ ! -e $HOME/Applications/Ghostty.app ]] \
  && mv "$copy/Ghostty.app" "$HOME/Applications/Ghostty.app"; then
  rmdir "$copy"
else
  rm -rf "$copy"
  exit 1
fi
printf 'Installed Ghostty %s without launching it.\n' "$version"
