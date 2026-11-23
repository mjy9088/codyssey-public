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
vnc_enabled=0
started=0
opened_fusion=0
cleanup() {
  if (( vnc_enabled )); then
    running=$(fusion list) || return 1
    if (( started )) && fusion_list_contains "$base" "$running"; then
      fusion_started=1
      if fusion_uses_lab_password; then
        vm_stop_disposable "$base" || return 1
      else
        vm_stop "$base" || return 1
      fi
      printf 'Stopped the guest to close its temporary console. Run step 04 again to resume.\n' >&2
    fi
    "$fusion_vmcli" "$base" ConfigParams SetEntry RemoteDisplay.vnc.enabled FALSE || return 1
  fi
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
  if (( opened_fusion )); then
    bash "$scripts/intel-macos-vm/07-close-fusion.sh" || :
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
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
prompt_id=$(od -An -N4 -tx1 /dev/urandom | tr -d '[:space:]')
printf '%s\n' "$prompt_id" > "$work/media/prompt-id"
lab_password=0
if fusion_uses_lab_password; then
  lab_password=1
  touch "$work/media/automatic-setup"
fi
cp "$scripts/intel-macos-vm/guest-setup.sh" "$work/media/setup.sh"
cat > "$work/media/Start Setup.command" <<'EOF'
#!/bin/bash
exec /bin/bash "$(dirname "$0")/setup.sh"
EOF
chmod 755 "$work/media/Start Setup.command"
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
printf 'Saved first-desktop snapshot: %s\n' "$checkpoint"
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.deviceType cdrom-image
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.fileName "$setup_iso"
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.startConnected TRUE
"$fusion_vmcli" "$base" ConfigParams SetEntry sata0:2.present TRUE
launcher="$scripts/intel-macos-vm"
if command -v python3 >/dev/null && xcrun --find swiftc >/dev/null 2>&1 &&
   ! grep -qiE '^RemoteDisplay\.vnc\.enabled[[:blank:]]*=[[:blank:]]*"TRUE"' "$base"; then
  printf 'Preparing the Finder screen recognizer.\n'
  if xcrun swiftc -module-cache-path "$storage/tools/swift-cache" "$launcher/recognize-screen.swift" -o "$work/recognize"; then
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    "$fusion_vmcli" "$base" ConfigParams SetEntry RemoteDisplay.vnc.ip 127.0.0.1
    "$fusion_vmcli" "$base" ConfigParams SetEntry RemoteDisplay.vnc.port "$port"
    vnc_enabled=1
    "$fusion_vmcli" "$base" ConfigParams SetEntry RemoteDisplay.vnc.enabled TRUE
  fi
fi
if ! pgrep -x 'VMware Fusion' >/dev/null; then
  opened_fusion=1
fi
started=1
fusion start "$base" gui
setup_opened=0
if (( vnc_enabled )); then
  if fusion_uses_lab_password; then
    printf 'Opening the guest setup disc and handling the lab account prompts.\n'
  else
    printf 'Waiting for Finder to show the guest setup file. Sign in to the guest if needed.\n'
  fi
  if CODYSSEY_FUSION_USE_LAB_PASSWORD=$lab_password \
    python3 "$launcher/open-guest-setup.py" "$fusion_vmcli" "$base" "$work/recognize" "$work/screen.png" "$port" "$guest_user" "$prompt_id"; then
    setup_opened=1
  fi
fi
if (( ! setup_opened )); then
  if fusion_uses_lab_password; then
    if [[ -f $work/screen.txt ]]; then
      cp "$work/screen.txt" "$storage/setup-screen.txt"
      printf 'Last setup OCR: %s/setup-screen.txt\n' "$storage" >&2
    fi
    printf 'Could not open the setup disc automatically in the selected VM.\n' >&2
    exit 1
  fi
  cat <<'EOF'
If Terminal did not open, double-click Start Setup.command on the Codyssey disc.
If needed, you can also start it from the guest Terminal:

bash /Volumes/Codyssey/setup.sh

EOF
fi
if ! fusion_uses_lab_password; then
  cat <<'EOF'
Approve VMware Tools and Command Line Tools if prompted. Restart the guest if
requested and rerun the command after signing in. Enable Remote Login for the
lab account. This command waits for the guest and continues automatically.
EOF
fi
CODYSSEY_FUSION_NAT_FALLBACK=1 CODYSSEY_FUSION_SETUP_OPENED=$setup_opened \
  bash "$scripts/intel-macos-vm/05-prepare-base.sh" "$base"
