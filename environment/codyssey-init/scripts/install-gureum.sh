#!/usr/bin/env bash
set -euo pipefail
umask 077

# Pin the package used for fresh installation; reuse an existing Gureum bundle.
version=1.13.2
checksum=eadbc2904e54885eea08f7c410e2adeec4caf8463c1321706cb3d1a3e42612d1
[[ $(uname -s) == Darwin ]] || { printf 'Gureum setup requires macOS.\n' >&2; exit 1; }
target="$HOME/Library/Input Methods/Gureum.app"
for app in "$target" '/Library/Input Methods/Gureum.app'; do
  [[ -e $app || -L $app ]] || continue
  info="$app/Contents/Info.plist"
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info" 2>/dev/null || true)
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info" 2>/dev/null || true)
  if [[ $identifier != org.youknowone.inputmethod.Gureum || -z $executable ||
        $executable == */* || ! -f $app/Contents/MacOS/$executable || ! -x $app/Contents/MacOS/$executable ]]; then
    printf 'Existing Gureum bundle is invalid: %s\n' "$app" >&2
    exit 1
  fi
  printf '%s\n' "$app"
  exit 0
done

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
