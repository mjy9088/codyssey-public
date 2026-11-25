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
convert_image() {
  local label=$1
  shift
  printf '%s…\n' "$label" >&2
  hdiutil convert -puppetstrings "$@" |
    LC_ALL=C awk '
      BEGIN { last = -5 }
      /^MESSAGE:/ { sub(/^MESSAGE:/, ""); print; fflush(); next }
      /^PERCENT:/ {
        value = int(substr($0, 9))
        if (value >= 0 && value < 100 && value >= last + 5) {
          print "Disk image conversion: " value "%"
          fflush()
          last = value
        }
        next
      }
      { print; fflush() }
    ' && printf 'Disk image conversion: 100%%\n'
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
mount_work=''
attached=0
cleanup() {
  if (( attached )) && { [[ -z $device ]] || ! hdiutil detach "$device" >&2; }; then
    printf 'Installer volume is still attached. Temporary image: %s\n' "$work" >&2
    return
  fi
  [[ -z $mount_work ]] || rm -rf -- "$mount_work"
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
  convert_image "Converting the recovery disk image" "$1" -format UDTO -o "$work/recovery"
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
# Disk Arbitration may refuse a private mount point nested on removable storage.
mount_work=$(mktemp -d /private/tmp/codyssey-media-mount.XXXXXX)
mount="$mount_work/volume"
mkdir "$mount"
hdiutil create -size 18g -type SPARSE -layout SPUD -fs HFS+J \
  -volname CodysseyInstaller "$work/installer.sparseimage"
hdiutil attach -nobrowse -mountpoint "$mount" -plist "$work/installer.sparseimage" > "$work/attachment.plist"
attached=1
candidate=$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:dev-entry' "$work/attachment.plist")
[[ $candidate =~ ^(/dev/disk[0-9]+)(s[0-9]+)*$ ]] || {
  printf 'Could not identify the attached installer image.\n' >&2
  exit 1
}
device=${BASH_REMATCH[1]}
if [[ ${CODYSSEY_FUSION_HOST_AUTH:-terminal} == dialog ]]; then
  printf 'Authorize writing the installer volume in the macOS dialog.\n' >&2
  /usr/bin/osascript - "$installer" "$mount" <<'APPLESCRIPT'
on run arguments
  set installer to quoted form of item 1 of arguments
  set targetVolume to quoted form of item 2 of arguments
  do shell script (installer & " --volume " & targetVolume & " --nointeraction") with administrator privileges
end run
APPLESCRIPT
else
  # Keep the authorization prompt ahead of the installer output.
  sudo -v -p 'Codyssey installer administrator password for %p: '
  printf 'Writing the installer volume…\n' >&2
  sudo -n "$installer" --volume "$mount" --nointeraction
fi
hdiutil detach "$device"
attached=0
if [[ $output == *.iso ]]; then
  convert_image "Converting the installer volume to ISO" "$work/installer.sparseimage" -format UDTO -o "$work/installer"
  ln "$work/installer.cdr" "$output"
else
  convert_image "Converting the installer volume to DMG" "$work/installer.sparseimage" -format UDRW -o "$work/installer.dmg"
  ln "$work/installer.dmg" "$output"
fi
printf 'In Fusion, select File > New > Install from disc or image and choose:\n%s\n' "$output"
