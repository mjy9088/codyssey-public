#!/usr/bin/env bash
# Format a newly allocated raw image and expose it as a Fusion SATA disk.
set -euo pipefail

[[ $# == 2 && -d $1 && -x $2 ]] || { printf 'Usage: bash %s VM_BUNDLE VDISKMANAGER\n' "$0" >&2; exit 2; }
bundle=$(CDPATH='' cd -- "$1" && pwd -P)
vmdk="$bundle/Target.vmdk"
[[ ! -e $vmdk && ! -L $vmdk ]] || {
  printf 'The target disk already exists.\n' >&2
  exit 1
}

umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/codyssey-disk.XXXXXX")
raw="$work/Target.raw"
device=
cleanup() {
  if [[ -n $device ]] && ! hdiutil detach "$device"; then
    printf 'The target image remains attached at %s.\n' "$device" >&2
    return 1
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkfile -n 80g "$raw"
hdiutil attach -nomount -readwrite -imagekey diskimage-class=CRawDiskImage -plist "$raw" > "$work/attached.plist"
candidate=$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:dev-entry' "$work/attached.plist")
[[ $candidate =~ ^/dev/disk[0-9]+$ ]] || { printf 'Expected a whole disk image device.\n' >&2; exit 1; }
device=$candidate
diskutil info -plist "$device" > "$work/device.plist"
[[ $(plutil -extract DeviceNode raw "$work/device.plist") == "$device" &&
   $(plutil -extract VirtualOrPhysical raw "$work/device.plist") == Virtual &&
   $(plutil -extract WholeDisk raw "$work/device.plist") == true &&
   $(plutil -extract TotalSize raw "$work/device.plist") == 85899345920 ]] || {
  printf 'Refusing to format an unexpected disk image device.\n' >&2
  exit 1
}
diskutil eraseDisk APFS 'Macintosh HD' GPT "$device"
diskutil list "$device"
hdiutil detach "$device"
device=
cat > "$work/Target-flat.vmdk" <<'VMDK'
# Disk DescriptorFile
version=1
encoding="UTF-8"
CID=fffffffe
parentCID=ffffffff
createType="monolithicFlat"
RW 167772160 FLAT "Target.raw" 0
ddb.adapterType = "lsilogic"
ddb.virtualHWVersion = "6"
VMDK
"$2" -r "$work/Target-flat.vmdk" -t 0 "$vmdk"
