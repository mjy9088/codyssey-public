#!/usr/bin/env bash
set -euo pipefail
umask 077

# Match the input method installed on the reference macOS environment.
version=1.13.2
checksum=eadbc2904e54885eea08f7c410e2adeec4caf8463c1321706cb3d1a3e42612d1
[[ $(uname -s) == Darwin ]] || { printf 'Gureum setup requires macOS.\n' >&2; exit 1; }
for app in '/Library/Input Methods/Gureum.app' "$HOME/Library/Input Methods/Gureum.app"; do
  if [[ -x $app/Contents/MacOS/Gureum ]] && [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist") == "$version" ]]; then
    printf '%s\n' "$app"
    exit 0
  fi
done

target="$HOME/Library/Input Methods/Gureum.app"
[[ ! -e $target ]] || { printf 'An existing per-user Gureum version differs from %s; move it aside first.\n' "$version" >&2; exit 1; }
stage=$(mktemp -d)
copy=
trap 'rm -rf "$stage"; [[ -z $copy ]] || rm -rf "$copy"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/gureum/gureum/releases/download/$version/Gureum-$version.pkg" -o "$stage/Gureum.pkg"
[[ $(shasum -a 256 "$stage/Gureum.pkg" | cut -d ' ' -f 1) == "$checksum" ]] || {
  printf 'Gureum package checksum verification failed.\n' >&2
  exit 1
}
/usr/sbin/pkgutil --expand-full "$stage/Gureum.pkg" "$stage/expanded"
source_app="$stage/expanded/org.youknowone.inputmethod.Gureum.pkg/Payload/Gureum.app"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist") == "$version" ]]
mkdir -p "$HOME/Library/Input Methods"
copy=$(mktemp -d "$HOME/Library/Input Methods/.codyssey-gureum.XXXXXX")
ditto "$source_app" "$copy/Gureum.app"
[[ -x $copy/Gureum.app/Contents/MacOS/Gureum ]]
[[ ! -e $target ]]
mv "$copy/Gureum.app" "$target"
rmdir "$copy"
copy=
printf '%s\n' "$target"
