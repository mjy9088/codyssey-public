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
if [[ ! -e $tools && ! -L $tools ]]; then
  download=$(mktemp "$storage/tools/.darwin.XXXXXX")
  trap 'rm -f -- "$download"' EXIT
  curl --fail --location --retry 2 --proto '=https' --proto-redir '=https' \
    https://packages-prod.broadcom.com/tools/frozen/darwin/darwin.iso -o "$download"
  digest=$(shasum -a 256 "$download")
  [[ ${digest%% *} == "$checksum" ]] || { printf 'VMware Tools ISO checksum mismatch.\n' >&2; exit 1; }
  ln "$download" "$tools"
fi
tools=$(fusion_media_path "$tools")
digest=$(shasum -a 256 "$tools")
[[ ${digest%% *} == "$checksum" ]] || { printf 'VMware Tools ISO checksum mismatch: %s\n' "$tools" >&2; exit 1; }

fusion_boot_target "$base"
fusion_disconnect_media "$base" sata0:2
checkpoint='macOS - initial setup complete'
snapshots=$(fusion listSnapshots "$base")
if ! grep -qxF "$checkpoint" <<< "$snapshots"; then
  fusion snapshot "$base" "$checkpoint"
fi
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.deviceType cdrom-image
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.fileName "$tools"
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.startConnected TRUE
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.present TRUE
fusion start "$base" gui
cat <<'EOF'
Paste this block into the guest Terminal:

pkg=$(find "/Volumes/VMware Tools" -name "VMware Tools.pkg" -print -quit)
if [ -n "$pkg" ] && signature=$(/usr/sbin/pkgutil --check-signature "$pkg") && printf '%s\n' "$signature" | grep -qF '(EG7KH642X6)'; then
  if ! sudo /usr/sbin/installer -pkg "$pkg" -target /; then
    services='/Library/Application Support/VMware Tools/services.sh'
    if [ -x "$services" ]; then sudo "$services" --start; fi
  fi
else
  printf '%s\n' 'The signed VMware Tools package was not found.'
fi
xcode-select -p >/dev/null 2>&1 || xcode-select --install

Approve VMware Tools and Command Line Tools if prompted. Restart the guest if
requested. Enable Remote Login for the lab account, then run step 05 on the host.
EOF
