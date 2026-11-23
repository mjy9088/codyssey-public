#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: bash %s --accept-license [--invalidate | --no-invalidate] [INSTALLER.app | INSTALLER.iso]\n' "$0"
}
accepted=0
cache_mode=auto
media=
while (( $# )); do
  case $1 in
    --help) usage; exit 0 ;;
    --accept-license) accepted=1 ;;
    --invalidate|--no-invalidate)
      if [[ $cache_mode != auto ]]; then usage >&2; exit 2; fi
      cache_mode=$1
      ;;
    *.app|*.iso)
      if [[ -n $media || $1 == -* ]]; then usage >&2; exit 2; fi
      media=$1
      ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done
(( accepted )) || {
  printf 'Read the macOS license at https://www.apple.com/legal/sla/ and pass --accept-license to authorize it.\n' >&2
  exit 2
}
launcher=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
scripts=${launcher%/*}
revision=$(git -C "$launcher" rev-parse --verify HEAD)
# shellcheck source=scripts/vm-fusion.sh
. "$scripts/vm-fusion.sh"
. "$scripts/vm-progress.sh"
fusion_require_intel
fusion_tools
if ! command -v python3 >/dev/null || ! xcrun --find swiftc >/dev/null; then
  printf 'Install Python 3 and Apple Command Line Tools on the host.\n' >&2
  exit 1
fi
umask 077
storage=$(fusion_storage_path)
mkdir -p "$storage/runs"
storage=$(CDPATH='' cd -- "$storage" && pwd -P)
cache="$storage/unattended-base"
# Keep the storage lock on the launcher's open descriptor across subprocesses.
exec 9>>"$storage/.unattended.lock"
python3 -c '
import fcntl
import sys

try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit("Another unattended Fusion run is using this storage volume.")
'

cached_status=pending
cached_revision=-
cached_run=-
cached_base=
if entry=$(fusion_read_selection "$cache"); then
  IFS=' ' read -r status origin candidate extra <<< "$entry"
  if [[ ( $status == passed || $status == pending ) && $origin =~ ^[0-9a-f]{40}$|^[0-9a-f]{64}$ &&
    $candidate =~ ^unattended\.[A-Za-z0-9]{6}$ && -z $extra ]]; then
    path="$storage/runs/$candidate"
    candidate_base="$path/bases/Sequoia.vmwarevm/Sequoia.vmx"
    if [[ -f $candidate_base && ! -L $candidate_base &&
      -s $path/credentials/id_ed25519 && -s $path/credentials/known_hosts ]]; then
      cached_status=$status
      cached_revision=$origin
      cached_run=$candidate
      cached_base=$candidate_base
    fi
  fi
fi

run=$(mktemp -d "$storage/runs/unattended.XXXXXX")
fusion_write_selection "$cache" "pending $cached_revision $cached_run"
fusion_write_selection "$run/git-commit" "$revision"
printf 'Run: %s\n' "$run"
reuse=0
if [[ -n $cached_base ]] && {
  [[ $cache_mode == --no-invalidate ]] ||
    [[ $cache_mode == auto && $cached_status == passed && $cached_revision == "$revision" ]]
}; then
  if snapshots=$(fusion listSnapshots "$cached_base") &&
    grep -Fx 'macOS - initial setup complete' <<< "$snapshots" >/dev/null; then
    fusion_require_stopped "$cached_base"
    reuse=1
  fi
fi
if (( reuse )); then
  base=$cached_base
  credentials="$storage/runs/$cached_run/credentials"
else
  base="$run/bases/Sequoia.vmwarevm/Sequoia.vmx"
  credentials="$run/credentials"
fi
export CODYSSEY_FUSION_STORAGE="$run"
export CODYSSEY_FUSION_UNATTENDED=1
export CODYSSEY_FUSION_CREDENTIALS="$credentials"
export CODYSSEY_FUSION_IDENTITY="$credentials/id_ed25519"
export CODYSSEY_FUSION_KNOWN_HOSTS="$credentials/known_hosts"
export CODYSSEY_FUSION_GUEST_USER=vmuser
export CODYSSEY_FUSION_NAT_FALLBACK=1
installer_console=0
opened_fusion=0

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

trap 'close_fusion || :; python3 -c "import fcntl; fcntl.flock(9, fcntl.LOCK_UN)" || :' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

vm_progress "Building the Fusion console recognizer" xcrun swiftc -module-cache-path "$storage/swift-cache" "$launcher/recognize-screen.swift" -o "$run/recognize"
if (( reuse )); then
  printf 'Reusing prepared base from commit %s: %s\n' "$cached_revision" "$base" | tee "$run/base-reuse.log"
  fusion_remember_base "$base"
else
  printf 'Preparing a new base for commit %s.\n' "$revision"
  if [[ $media == *.iso ]]; then
    installer=$(fusion_media_path "$media")
    mkdir "$run/installers"
    local_iso="$run/installers/Sequoia-local.iso"
    {
      if [[ $(stat -f %d "$installer") == "$(stat -f %d "$run/installers")" ]]; then
        vm_progress_path="$local_iso" vm_progress "Staging the installer ISO" cp -c "$installer" "$local_iso"
      else
        vm_progress "Copying the installer ISO" rsync --progress -- "$installer" "$local_iso"
      fi
    } 2>&1 | tee "$run/01-media.log"
    fusion_remember_media "$run/installers/Sequoia-local.iso"
    printf 'Staged the Apple installer ISO from %s.\n' "$installer" | tee -a "$run/01-media.log"
  elif [[ -n $media ]]; then
    bash "$launcher/01-create-install-media.sh" --app "$media" 2>&1 | tee "$run/01-media.log"
  else
    installer_cache="$storage/installer-cache"
    CODYSSEY_FUSION_STORAGE="$installer_cache" bash "$launcher/01-create-install-media.sh" 2>&1 |
      tee "$run/01-media.log"
    installer=$(CODYSSEY_FUSION_STORAGE="$installer_cache" fusion_selected_media)
    fusion_remember_media "$installer"
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
  cached_revision=$revision
  cached_run=${run##*/}
  fusion_write_selection "$cache" "pending $cached_revision $cached_run"
fi
CODYSSEY_FUSION_VERIFY_RECOGNIZER="$run/recognize" \
  bash "$launcher/06-verify-workstation.sh" "$base" 2>&1 | tee "$run/06-verify.log"
finish_run 2>&1 | tee "$run/07-cleanup.log"
fusion_write_selection "$cache" "passed $cached_revision $cached_run"
opened_fusion=0
printf 'PASS: Intel macOS installation and workstation verification. Run: %s\n' "$run"
