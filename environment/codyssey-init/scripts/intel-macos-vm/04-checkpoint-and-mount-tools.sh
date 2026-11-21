#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help || $# -gt 1 ]]; then
  printf 'Usage: bash %s [BASE.vmx]\n' "$0"
  [[ ${1:-} == --help ]]
  exit
fi
scripts=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
# shellcheck source=scripts/vm-fusion.sh
. "$scripts/vm-fusion.sh"
fusion_require_intel
fusion_tools
base=$(fusion_selected_base "${1:-}")
fusion_require_stopped "$base"
storage=$(fusion_storage_path)
tools="$storage/tools/darwin.iso"
checksum=e0c96286f376b30e2c2362bd991709f0f6bc6ebd911be4056a58da8698c49236
umask 077
mkdir -p "$storage/tools"
work=$(mktemp -d "${TMPDIR:-/tmp}/codyssey-setup.XXXXXX")
mount="$work/darwin"
mounted=0
stage=
cache_stage=
cleanup() {
  if [[ -n $stage ]]; then
    rm -rf -- "$stage"
  fi
  if [[ -n $cache_stage ]]; then
    rm -rf -- "$cache_stage"
  fi
  if (( mounted )) && ! hdiutil detach "$mount" >/dev/null; then
    printf 'Tools image is still mounted at %s.\n' "$mount" >&2
    return
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT
if [[ ! -e $tools && ! -L $tools ]]; then
  cache_stage=$(mktemp -d "$storage/tools/.download.XXXXXX")
  download="$cache_stage/darwin.iso"
  curl --fail --location --retry 2 --proto '=https' --proto-redir '=https' \
    https://packages-prod.broadcom.com/tools/frozen/darwin/darwin.iso -o "$download"
  digest=$(shasum -a 256 "$download")
  [[ ${digest%% *} == "$checksum" ]] || { printf 'VMware Tools ISO checksum mismatch.\n' >&2; exit 1; }
  ln "$download" "$tools"
fi
tools=$(fusion_media_path "$tools")

identity=$(fusion_guest_identity)
fusion_ensure_guest_identity "$identity"
guest_user=${CODYSSEY_FUSION_GUEST_USER:-vmuser}
[[ $guest_user =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || { printf 'Invalid guest account name.\n' >&2; exit 1; }
mkdir "$mount" "$work/media"
if [[ -r $identity.pub ]]; then
  read -r key_type key_blob _ < "$identity.pub"
else
  public_key=$(ssh-keygen -y -f "$identity")
  read -r key_type key_blob _ <<< "$public_key"
fi
[[ $key_type == ssh-ed25519 && $key_blob =~ ^[A-Za-z0-9+/=]+$ ]] || {
  printf 'Expected an Ed25519 public key.\n' >&2
  exit 1
}
printf '%s %s\n' "$key_type" "$key_blob" > "$work/media/host.pub"
ssh-keygen -lf "$work/media/host.pub" >/dev/null
printf '%s\n' "$guest_user" > "$work/media/guest-user"
cp "$scripts/intel-macos-vm/guest-setup.sh" "$work/media/setup.sh"
# DiskImages requires access to both paths, including when the cache is on removable storage.
cp "$tools" "$work/darwin.iso"
digest=$(shasum -a 256 "$work/darwin.iso")
[[ ${digest%% *} == "$checksum" ]] || { printf 'VMware Tools ISO checksum mismatch: %s\n' "$tools" >&2; exit 1; }
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$work/darwin.iso" >/dev/null
mounted=1
package=$(find "$mount" -name 'VMware Tools.pkg' -print -quit)
[[ -n $package ]] || { printf 'VMware Tools package missing from the verified image.\n' >&2; exit 1; }
ditto "$package" "$work/media/VMware Tools.pkg"
hdiutil detach "$mount" >/dev/null
mounted=0
setup_iso="${base%/*}/Codyssey-Guest-Setup.iso"
[[ ! -L $setup_iso && ( ! -e $setup_iso || -f $setup_iso ) ]] || exit 1
stage=$(mktemp -d "${base%/*}/.guest-setup.XXXXXX")
hdiutil makehybrid -hfs -iso -joliet -default-volume-name Codyssey -o "$stage/setup.iso" "$work/media"
mv -f "$stage/setup.iso" "$setup_iso"
setup_iso=$(fusion_media_path "$setup_iso")

fusion_boot_target "$base"
fusion_disconnect_media "$base" sata0:2
checkpoint='macOS - initial setup complete'
snapshots=$(fusion listSnapshots "$base")
if ! grep -qxF "$checkpoint" <<< "$snapshots"; then
  fusion snapshot "$base" "$checkpoint"
fi
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.deviceType cdrom-image
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.fileName "$setup_iso"
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.startConnected TRUE
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.present TRUE
fusion start "$base" gui
cat <<'EOF'
In the guest Terminal, run:

bash /Volumes/Codyssey/setup.sh

Approve VMware Tools and Command Line Tools if prompted. Restart the guest if
requested and rerun the command after signing in. Enable Remote Login for the
lab account. This command waits for the guest and continues automatically.
EOF
bash "$scripts/intel-macos-vm/05-prepare-base.sh" "$base"
