#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $(uname -s) == Darwin ]] || { printf 'iTerm2 setup requires macOS.\n' >&2; exit 1; }
# Universal official archive; checksum from Homebrew's iTerm2 cask.
# https://formulae.brew.sh/api/cask/iterm2.json
version=3.7.7
checksum=549eb2b21464d7f4606165e51c36a6b1a252ac9a79958228a240152412759da2
plistbuddy_bin=${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}
for app in "${CODYSSEY_APPLICATIONS_DIR:-/Applications}/iTerm.app" "$HOME/Applications/iTerm.app"; do
  if [[ -d $app ]]; then
    [[ $("$plistbuddy_bin" -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == com.googlecode.iterm2 ]]
    [[ -x $app/Contents/MacOS/iTerm2 ]]
    printf 'Reusing %s\n' "$app"
    exit 0
  fi
done
stage=$(mktemp -d)
copy=
trap 'rm -rf "$stage"; [[ -z $copy ]] || rm -rf "$copy"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
curl --fail --location --silent --show-error --retry 3 \
  "https://iterm2.com/downloads/stable/iTerm2-${version//./_}.zip" -o "$stage/iTerm2.zip"
[[ $(shasum -a 256 "$stage/iTerm2.zip" | cut -d ' ' -f 1) == "$checksum" ]] || {
  printf 'iTerm2 checksum verification failed.\n' >&2; exit 1;
}
ditto -x -k "$stage/iTerm2.zip" "$stage/extracted"
source_app="$stage/extracted/iTerm.app"
[[ $("$plistbuddy_bin" -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist") == com.googlecode.iterm2 ]]
[[ $("$plistbuddy_bin" -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist") == "$version" ]]
mkdir -p "$HOME/Applications"
copy=$(mktemp -d "$HOME/Applications/.codyssey-iterm2.XXXXXX")
ditto "$source_app" "$copy/iTerm.app"
[[ -x $copy/iTerm.app/Contents/MacOS/iTerm2 && ! -e $HOME/Applications/iTerm.app ]]
mv "$copy/iTerm.app" "$HOME/Applications/iTerm.app"
rmdir "$copy"
copy=
printf 'Installed iTerm2 %s without launching it.\n' "$version"
