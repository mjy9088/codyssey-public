#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help ]]; then
  printf 'Usage: CODYSSEY_FUSION_GUEST_PASSWORD_FILE=/path/to/private/file bash %s --accept-license [INSTALLER.app | INSTALLER.iso]\n' "$0"
  exit 0
fi
[[ ${1:-} == --accept-license && $# -le 2 ]] || {
  printf 'Read the macOS license at https://www.apple.com/legal/sla/ and pass --accept-license to authorize it.\n' >&2
  exit 2
}
launcher=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
scripts=${launcher%/*}
# shellcheck source=scripts/vm-fusion.sh
. "$scripts/vm-fusion.sh"
fusion_require_intel
fusion_tools
if ! command -v python3 >/dev/null || ! xcrun --find swiftc >/dev/null; then
  printf 'Install Python 3 and Apple Command Line Tools on the host.\n' >&2
  exit 1
fi
[[ -n ${CODYSSEY_FUSION_GUEST_PASSWORD_FILE:-} ]] || {
  printf 'Set CODYSSEY_FUSION_GUEST_PASSWORD_FILE to a private file containing the disposable guest password.\n' >&2
  exit 2
}
python3 "$launcher/guest_credential.py" >/dev/null
umask 077
storage=$(fusion_storage_path)
mkdir -p "$storage/runs"
storage=$(CDPATH='' cd -- "$storage" && pwd -P)
run=$(mktemp -d "$storage/runs/unattended.XXXXXX")
export CODYSSEY_FUSION_STORAGE="$run"
export CODYSSEY_FUSION_UNATTENDED=1
export CODYSSEY_FUSION_CREDENTIALS="$run/credentials"
export CODYSSEY_FUSION_GUEST_USER=vmuser
export CODYSSEY_FUSION_NAT_FALLBACK=1
base="$run/bases/Sequoia.vmwarevm/Sequoia.vmx"
installer_console=0
opened_fusion=0
printf 'Run: %s\n' "$run"

close_fusion() {
  local running completed=${1:-0}
  if (( installer_console )) && [[ -f $base ]]; then
    running=$(fusion list) || return 1
    if fusion_list_contains "$base" "$running"; then
      fusion_started=1
      vm_stop_disposable "$base" || return 1
    fi
    "$fusion_vmcli" "$base" ConfigParams SetEntry RemoteDisplay.vnc.enabled FALSE || return 1
  fi
  if (( opened_fusion || completed )); then
    running=$(fusion list) || return 1
    if [[ $running == 'Total running VMs: 0' ]]; then
      bash "$launcher/07-close-fusion.sh" || return 1
    else
      printf 'Fusion is still in use by other VMs. Left the application open.\n'
    fi
  fi
}

finish_run() {
  local vmx
  close_fusion 1 || return
  # Fusion's GUI can hold the VMX even after the guest stops.
  for vmx in "$run"/verification/*.vmwarevm/*.vmx; do
    [[ -f $vmx ]] || continue
    if ! fusion deleteVM "$vmx"; then
      printf 'Stopped clone retained at %s. Close its Fusion window and use vmrun deleteVM to remove it.\n' "${vmx%/*}" >&2
      return 1
    fi
    if [[ -e ${vmx%/*} ]]; then
      printf 'Fusion left files in the verification bundle: %s\n' "${vmx%/*}" >&2
      return 1
    fi
    printf 'Removed verification clone: %s\n' "${vmx%/*}"
  done
}

trap 'close_fusion || :' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

xcrun swiftc -module-cache-path "$storage/swift-cache" "$launcher/recognize-screen.swift" -o "$run/recognize"
if [[ $# == 2 ]]; then
  if [[ $2 == *.iso ]]; then
    installer=$(fusion_media_path "$2")
    mkdir "$run/installers"
    cp -c "$installer" "$run/installers/Sequoia-local.iso" ||
      cp "$installer" "$run/installers/Sequoia-local.iso"
    fusion_remember_media "$run/installers/Sequoia-local.iso"
    printf 'Staged the Apple installer ISO from %s.\n' "$installer" | tee "$run/01-media.log"
  else
    bash "$launcher/01-create-install-media.sh" --app "$2" 2>&1 | tee "$run/01-media.log"
  fi
else
  bash "$launcher/01-create-install-media.sh" 2>&1 | tee "$run/01-media.log"
fi
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
if ! pgrep -x 'VMware Fusion' >/dev/null; then
  opened_fusion=1
fi
installer_console=1
CODYSSEY_FUSION_INSTALL_CONSOLE_PORT=$port bash "$launcher/02-create-base-vm.sh" 2>&1 | tee "$run/02-create.log"
python3 "$launcher/install-guest.py" "$base" "$fusion_vmcli" "$run/recognize" "$run" "$port" --accept-license \
  2>&1 | tee "$run/03-installer.log"
"$fusion_vmcli" "$base" ConfigParams SetEntry RemoteDisplay.vnc.enabled FALSE
installer_console=0
bash "$launcher/04-checkpoint-and-mount-tools.sh" "$base" 2>&1 | tee "$run/04-prepare.log"
CODYSSEY_FUSION_VERIFY_RECOGNIZER="$run/recognize" \
  bash "$launcher/06-verify-workstation.sh" "$base" 2>&1 | tee "$run/06-verify.log"
finish_run 2>&1 | tee "$run/07-cleanup.log"
trap - EXIT
printf 'PASS: Intel macOS installation and workstation verification. Run: %s\n' "$run"
