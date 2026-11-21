#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: bash scripts/create-fusion-installer.sh INSTALLER.app OUTPUT.dmg|OUTPUT.iso\n'
  printf '       bash scripts/create-fusion-installer.sh --recovery BaseSystem.dmg OUTPUT.vmdk\n'
}
[[ ${1:-} != --help ]] || { usage; exit 0; }
recovery=0
if [[ ${1:-} == --recovery ]]; then
  recovery=1
  shift
  [[ $# == 2 && $1 == *.dmg && $2 == *.vmdk && -f $1 ]] || { usage >&2; exit 2; }
else
  [[ $# == 2 && $1 == *.app && ( $2 == *.dmg || $2 == *.iso ) ]] || { usage >&2; exit 2; }
fi
[[ $(uname -s) == Darwin && $(uname -m) == x86_64 ]] || {
  printf 'Build this VMware Fusion installer on an Intel Mac.\n' >&2
  exit 1
}
umask 077
mkdir -p -- "$(dirname -- "$2")"
directory=$(CDPATH='' cd -- "$(dirname -- "$2")" && pwd -P)
output="$directory/$(basename -- "$2")"
[[ ! -e $output && ! -L $output ]] || {
  printf 'Installer already exists: %s\n' "$output" >&2
  exit 1
}

work=$(mktemp -d "$directory/.fusion-installer.XXXXXX")
device=''
attached=0
cleanup() {
  if (( attached )) && { [[ -z $device ]] || ! hdiutil detach "$device" >&2; }; then
    printf 'Installer volume is still attached. Temporary image: %s\n' "$work" >&2
    return
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if (( recovery )); then
  backing_file=${output##*/}
  backing_file=${backing_file%.vmdk}.cdr
  [[ $backing_file =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && ! -e $directory/$backing_file && ! -L $directory/$backing_file ]] || {
    printf 'Use a new recovery filename with letters, digits, periods, hyphens or underscores.\n' >&2
    exit 1
  }
  hdiutil convert "$1" -format UDTO -o "$work/recovery"
  bytes=$(stat -f %z "$work/recovery.cdr")
  (( bytes > 0 && bytes % 512 == 0 )) || { printf 'Invalid recovery disk size.\n' >&2; exit 1; }
  cat > "$work/recovery.vmdk" <<EOF
# Disk DescriptorFile
version=1
encoding="UTF-8"
CID=fffffffe
parentCID=ffffffff
createType="monolithicFlat"
RW $((bytes / 512)) FLAT "$backing_file" 0
ddb.adapterType = "lsilogic"
ddb.virtualHWVersion = "6"
EOF
  ln "$work/recovery.cdr" "$directory/$backing_file"
  ln "$work/recovery.vmdk" "$output"
  printf 'Recovery disk: %s\n' "$output"
  exit 0
fi

installer=$(CDPATH='' cd -- "$1" && pwd -P)/Contents/Resources/createinstallmedia
[[ -x $installer ]] || { printf 'Use a full macOS installer app from Apple.\n' >&2; exit 1; }
mount="$work/volume"
mkdir "$mount"
hdiutil create -size 18g -type SPARSE -layout SPUD -fs HFS+J \
  -volname CodysseyInstaller "$work/installer.sparseimage"
attached=1
hdiutil attach -nobrowse -mountpoint "$mount" -plist "$work/installer.sparseimage" > "$work/attachment.plist"
candidate=$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:dev-entry' "$work/attachment.plist")
[[ $candidate =~ ^(/dev/disk[0-9]+)(s[0-9]+)*$ ]] || {
  printf 'Could not identify the attached installer image.\n' >&2
  exit 1
}
device=${BASH_REMATCH[1]}
sudo "$installer" --volume "$mount" --nointeraction
hdiutil detach "$device"
attached=0
if [[ $output == *.iso ]]; then
  hdiutil convert "$work/installer.sparseimage" -format UDTO -o "$work/installer"
  ln "$work/installer.cdr" "$output"
else
  hdiutil convert "$work/installer.sparseimage" -format UDRW -o "$work/installer.dmg"
  ln "$work/installer.dmg" "$output"
fi
printf 'In Fusion, select File > New > Install from disc or image and choose:\n%s\n' "$output"
