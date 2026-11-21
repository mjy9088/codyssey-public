#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: bash %s [NAME INSTALLER.iso | [NAME] --recovery [BaseSystem.dmg]]\n' "$0"
}
[[ ${1:-} != --help ]] || { usage; exit 0; }
scripts=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
# shellcheck source=scripts/vm-fusion.sh
. "$scripts/vm-fusion.sh"
fusion_require_intel
if [[ $# == 0 ]]; then
  installer=$(fusion_selected_media)
  set -- Sequoia "$installer"
elif [[ $1 == --recovery ]]; then
  set -- Sequoia-Recovery "$@"
fi
[[ ( $# == 2 && ( $2 == *.iso || $2 == --recovery ) ) ||
   ( $# == 3 && $2 == --recovery && $3 == *.dmg ) ]] || { usage >&2; exit 2; }
name=$1
[[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { usage >&2; exit 2; }
fusion_tools
vdiskmanager="${fusion_vmrun%/*}/vmware-vdiskmanager"
[[ -x $vdiskmanager ]] || { printf 'VMware Virtual Disk Manager was not found.\n' >&2; exit 1; }
media=''
mounted_recovery=''
# Invoked by the EXIT trap only when this run mounted Recovery.
# shellcheck disable=SC2329
unmount_recovery() {
  if [[ -n $mounted_recovery ]]; then
    diskutil unmount "$mounted_recovery" >/dev/null || printf 'Recovery is still mounted: %s\n' "$mounted_recovery" >&2
  fi
}
trap unmount_recovery EXIT
if [[ $2 != --recovery ]]; then
  media=$(fusion_media_path "$2")
elif [[ $# == 3 ]]; then
  media=$(fusion_media_path "$3")
else
  # Restrict automatic discovery to the Recovery directory for the host OS.
  host_disk=$(diskutil info -plist /)
  group=$(plutil -extract APFSVolumeGroupID raw - <<< "$host_disk")
  [[ $(sw_vers -productVersion) == 15.* && $group =~ ^[[:xdigit:]-]{36}$ ]] || {
    printf 'Pass a Sequoia BaseSystem.dmg explicitly for this host.\n' >&2
    exit 1
  }
  for recovery in /System/Volumes/Recovery /Volumes/Recovery; do
    if [[ -s $recovery/$group/BaseSystem.dmg ]]; then
      media="$recovery/$group/BaseSystem.dmg"
      break
    fi
  done
  if [[ -z $media ]]; then
    container=$(plutil -extract APFSContainerReference raw - <<< "$host_disk")
    volumes=$(diskutil apfs list "$container" -plist)
    recovery_devices=()
    index=0
    while disk=$(plutil -extract "Containers.0.Volumes.$index.DeviceIdentifier" raw - <<< "$volumes" 2>/dev/null); do
      role=$(plutil -extract "Containers.0.Volumes.$index.Roles.0" raw - <<< "$volumes" 2>/dev/null) || role=''
      [[ $role != Recovery ]] || recovery_devices+=("$disk")
      index=$((index + 1))
    done
    if [[ ${#recovery_devices[@]} == 1 && ${recovery_devices[0]} =~ ^disk[0-9]+s[0-9]+$ ]]; then
      disk=${recovery_devices[0]}
      mount=$(diskutil info -plist "$disk" | plutil -extract MountPoint raw - 2>/dev/null) || mount=''
      if [[ -z $mount ]] && diskutil mount readOnly "$disk"; then
        mounted_recovery=$disk
        mount=$(diskutil info -plist "$disk" | plutil -extract MountPoint raw - 2>/dev/null) || mount=''
      fi
      if [[ -n $mount && -s $mount/$group/BaseSystem.dmg ]]; then
        media="$mount/$group/BaseSystem.dmg"
      fi
    fi
  fi
  [[ -n $media ]] || {
    printf 'Mount the host Recovery volume read-only or pass BaseSystem.dmg explicitly.\n' >&2
    exit 1
  }
fi
umask 077
storage=$(fusion_storage_path)
mkdir -p "$storage/bases"
bundle="$(CDPATH='' cd -- "$storage/bases" && pwd -P)/$name.vmwarevm"
mkdir "$bundle" || { printf 'Choose a new base name. Existing path: %s\n' "$bundle" >&2; exit 1; }
printf 'Creating base: %s\n' "$bundle"
"$vdiskmanager" -c -s 80GB -a lsilogic -t 0 "$bundle/Target.vmdk"

vmx="$bundle/$name.vmx"
cat > "$vmx" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "22"
displayName = "$name"
guestOS = "darwin24-64"
firmware = "efi"
smc.present = "TRUE"
board-id.reflectHost = "TRUE"
ich7m.present = "TRUE"
numvcpus = "4"
memsize = "8192"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = "Target.vmdk"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "generated"
isolation.tools.hgfs.disable = "TRUE"
sharedFolder.maxNum = "0"
EOF
for bridge in 4 5 6 7; do
  printf 'pciBridge%s.present = "TRUE"\npciBridge%s.virtualDev = "pcieRootPort"\npciBridge%s.functions = "8"\n' \
    "$bridge" "$bridge" "$bridge" >> "$vmx"
done
printf 'pciBridge0.present = "TRUE"\n' >> "$vmx"
if [[ $2 == --recovery ]]; then
  bash "$scripts/create-fusion-installer.sh" --recovery "$media" "$bundle/RecoveryMedia.vmdk"
  cat >> "$vmx" <<'EOF'
sata0:1.present = "TRUE"
sata0:1.startConnected = "TRUE"
sata0:1.fileName = "RecoveryMedia.vmdk"
sata0:1.mode = "independent-nonpersistent"
bios.hddOrder = "sata0:1,sata0:0"
EOF
else
  cat >> "$vmx" <<EOF
sata0:1.present = "TRUE"
sata0:1.startConnected = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "$media"
efi.bootOrder = "cdrom,hdd"
EOF
fi
printf 'Base VMX: %s\n' "$vmx"
fusion_remember_base "$vmx"
fusion start "$vmx" gui
