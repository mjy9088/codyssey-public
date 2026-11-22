#!/usr/bin/env bash
# Fusion owns the VMX lifecycle. VMware Tools supplies the address; SSH
# supplies command status, output, and archive input without guest passwords.
fusion_require_intel() {
  [[ $(uname -s) == Darwin && $(uname -m) == x86_64 ]] || {
    printf 'This command requires an Intel Mac with VMware Fusion Pro.\n' >&2
    return 1
  }
}

fusion_tools() {
  fusion_vmrun=${CODYSSEY_FUSION_VMRUN:-/Applications/VMware Fusion.app/Contents/Library/vmrun}
  [[ $fusion_vmrun == /* && -x $fusion_vmrun ]] || {
    printf 'Install VMware Fusion Pro or set CODYSSEY_FUSION_VMRUN to its vmrun path.\n' >&2
    return 1
  }
  fusion_vmcli=${fusion_vmrun%/*}/vmcli
  [[ -x $fusion_vmcli ]] || {
    printf 'Fusion requires vmcli alongside vmrun for offline VM configuration.\n' >&2
    return 1
  }
}

fusion_source_path() {
  local image=$1
  [[ $image == *.vmx && -f $image && ! -L $image && $image != *$'\n'* ]] || {
    printf 'Choose the local .vmx of the disposable Fusion VM.\n' >&2
    return 1
  }
  local directory
  directory=$(CDPATH='' cd -- "$(dirname -- "$image")" && pwd -P) || return
  printf '%s/%s\n' "$directory" "$(basename -- "$image")"
}

fusion_storage_path() {
  local config="$HOME/.local/share/codyssey/fusion" stored
  if [[ -n ${CODYSSEY_FUSION_STORAGE:-} ]]; then
    printf '%s\n' "$CODYSSEY_FUSION_STORAGE"
  elif [[ -e $config/storage-path || -L $config/storage-path ]]; then
    if stored=$(fusion_read_selection "$config/storage-path") && [[ $stored == /* ]]; then
      printf '%s\n' "$stored"
    else
      printf 'Invalid Fusion storage selection. Run step 01 with --set-storage.\n' >&2
      return 1
    fi
  else
    printf '%s\n' "$config"
  fi
}

fusion_guest_identity() {
  local credentials=${CODYSSEY_FUSION_CREDENTIALS:-"$HOME/.local/share/codyssey/fusion/credentials"}
  printf '%s\n' "${CODYSSEY_FUSION_IDENTITY:-"$credentials/id_ed25519"}"
}

fusion_ensure_guest_identity() {
  local identity=$1
  local -a key_options
  key_options=(-t ed25519 -C codyssey-fusion-lab -f "$identity")
  if [[ ${CODYSSEY_FUSION_UNATTENDED:-0} == 1 ]]; then
    # This disposable key lives in the private run directory.
    key_options+=(-N '')
  fi
  [[ $identity == /* ]] || { printf 'Use an absolute SSH identity path.\n' >&2; return 1; }
  if [[ ! -e $identity && ! -e $identity.pub && ! -L $identity && ! -L $identity.pub ]]; then
    (umask 077; mkdir -p "${identity%/*}" && ssh-keygen "${key_options[@]}") || return
  fi
  [[ -f $identity && -r $identity ]] || { printf 'Missing private key: %s\n' "$identity" >&2; return 1; }
}

fusion_read_selection() {
  local file=$1 value
  [[ -f $file && ! -L $file ]] || return 1
  value=$(cat -- "$file") || return
  [[ -n $value && $value != *$'\n'* && $value != *$'\r'* ]] || return 1
  printf '%s\n' "$value"
}

fusion_write_selection() (
  local file=$1 value=$2 temporary
  umask 077
  mkdir -p "${file%/*}" || return
  [[ ! -L $file && ( ! -e $file || -f $file ) ]] || {
    printf 'Cannot save the selection in %s.\n' "$file" >&2
    return 1
  }
  temporary=$(mktemp "${file%/*}/.selection.XXXXXX") || return
  trap 'rm -f -- "$temporary"' EXIT
  printf '%s\n' "$value" > "$temporary" && mv -f "$temporary" "$file"
)

fusion_select_storage() {
  local directory=$1
  [[ $directory != *$'\n'* && $directory != *$'\r'* && -n $directory ]] || return 1
  mkdir -p -- "$directory" || return
  directory=$(CDPATH='' cd -- "$directory" && pwd -P) || return
  fusion_write_selection "$HOME/.local/share/codyssey/fusion/storage-path" "$directory" || return
  printf 'Fusion storage: %s\n' "$directory"
}

fusion_selected_media() {
  local storage media
  storage=$(fusion_storage_path) || return
  media=$(fusion_read_selection "$storage/current-installer") || {
    printf 'No saved installer. Run step 01 or pass an ISO to step 02.\n' >&2
    return 1
  }
  [[ $media == /* ]] || media="$storage/$media"
  fusion_media_path "$media"
}

fusion_remember_media() {
  local media storage
  media=$(fusion_media_path "$1") || return
  storage=$(fusion_storage_path) || return
  storage=$(CDPATH='' cd -- "$storage" && pwd -P) || return
  fusion_write_selection "$storage/current-installer" "${media#"$storage/"}"
}

fusion_selected_base() {
  local base=${1:-} storage
  if [[ -z $base ]]; then
    storage=$(fusion_storage_path) || return
    base=$(fusion_read_selection "$storage/current-base") || {
      printf 'No saved base. Run step 02 or pass the path to a base VMX.\n' >&2
      return 1
    }
    [[ $base == /* ]] || base="$storage/$base"
  fi
  fusion_source_path "$base"
}

fusion_remember_base() {
  local base storage
  base=$(fusion_source_path "$1") || return
  storage=$(fusion_storage_path) || return
  mkdir -p "$storage" || return
  storage=$(CDPATH='' cd -- "$storage" && pwd -P) || return
  fusion_write_selection "$storage/current-base" "${base#"$storage/"}"
}

vm_init() {
  local image=$1 name=$2
  fusion_isolated=0 fusion_started=0
  fusion_project_root=${3:-}
  fusion_console_pid='' fusion_console_enabled=0
  fusion_tools || return
  fusion_source=$(fusion_source_path "$image") || return
  fusion_user=${CODYSSEY_FUSION_GUEST_USER:-}
  fusion_known_hosts=${CODYSSEY_FUSION_KNOWN_HOSTS:-}
  [[ $fusion_user =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ &&
     $fusion_known_hosts == /* && -f $fusion_known_hosts && -r $fusion_known_hosts &&
     $fusion_known_hosts != *'"'* && $fusion_known_hosts != *$'\n'* ]] || {
    printf 'Set CODYSSEY_FUSION_GUEST_USER and an absolute CODYSSEY_FUSION_KNOWN_HOSTS path.\n' >&2
    return 1
  }
  fusion_bundle="$(pwd -P)/$name.vmwarevm"
  fusion_vmx="$fusion_bundle/$name.vmx"
}

fusion() { "$fusion_vmrun" -T fusion "$@"; }

fusion_media_path() {
  local image=$1 directory result
  [[ -s $image && -f $image ]] || { printf 'Missing media: %s\n' "$image" >&2; return 1; }
  directory=$(CDPATH='' cd -- "$(dirname -- "$image")" && pwd -P) || return
  result="$directory/$(basename -- "$image")"
  [[ $result != *['"|']* && $result != *$'\n'* && $result != *$'\r'* ]] || {
    printf 'Use a media path without quotes, vertical bars, or line breaks.\n' >&2
    return 1
  }
  printf '%s\n' "$result"
}

fusion_require_stopped() {
  local vmx=$1 running suspended
  running=$(fusion list) || return
  if fusion_list_contains "$vmx" "$running"; then
    printf 'Shut down the Fusion VM first: %s\n' "$vmx" >&2
    return 1
  fi
  # A suspended VM can be absent from the running inventory.
  for suspended in "${vmx%/*}"/*.vmss; do
    [[ -f $suspended ]] || continue
    printf 'Resume and shut down the suspended Fusion VM first: %s\n' "$vmx" >&2
    return 1
  done
}

fusion_disconnect_media() {
  local vmx=$1 slot=$2 backing
  backing=$(awk -F'"' -v key="$slot.filename" 'NF >= 2 {
    field=tolower($1); sub(/^[[:blank:]]+/, "", field); sub(/[[:blank:]]*=.*$/, "", field);
    if (field == key) print $2;
  }' "$vmx") || return
  case $backing in
    ''|*.iso|*.dmg|RecoveryMedia.vmdk) ;;
    *) printf 'The %s slot contains another disk: %s\n' "$slot" "$backing" >&2; return 1 ;;
  esac
  "$fusion_vmcli" "$1" ConfigParams SetEntry "$2.present" FALSE
}

fusion_boot_target() {
  fusion_disconnect_media "$1" sata0:1 &&
    "$fusion_vmcli" "$1" ConfigParams SetEntry bios.hddOrder sata0:0 &&
    "$fusion_vmcli" "$1" ConfigParams SetEntry efi.bootOrder hdd,cdrom
}

vm_clone() {
  fusion_require_stopped "$fusion_source" || return
  # Reserve the bundle atomically and never act on a pre-existing destination.
  (umask 077; mkdir "$fusion_bundle") || return
  if ! fusion clone "$fusion_source" "$fusion_vmx" full "-cloneName=$name"; then
    printf 'Fusion clone failed. Inspect the reserved bundle at %s.\n' "$fusion_bundle" >&2
    return 1
  fi
}

fusion_list_contains() {
  local line
  while IFS= read -r line; do
    if [[ $line == "$1" || $line -ef $1 ]]; then
      return 0
    fi
  done <<< "$2"
  return 1
}

vm_start() {
  local mode=${CODYSSEY_FUSION_START_MODE:-gui} port
  [[ $mode == gui || $mode == nogui ]] || {
    printf 'Set CODYSSEY_FUSION_START_MODE to gui or nogui.\n' >&2
    return 1
  }
  "$fusion_vmcli" "$fusion_vmx" ConfigParams SetEntry isolation.tools.hgfs.disable TRUE || return
  "$fusion_vmcli" "$fusion_vmx" ConfigParams SetEntry sharedFolder.maxNum 0 || return
  fusion_isolated=1
  if [[ -n ${CODYSSEY_FUSION_VERIFY_RECOGNIZER:-} ]]; then
    [[ -x $CODYSSEY_FUSION_VERIFY_RECOGNIZER && -n $fusion_project_root ]] || return 1
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])') || return
    "$fusion_vmcli" "$fusion_vmx" ConfigParams SetEntry RemoteDisplay.vnc.ip 127.0.0.1 || return
    "$fusion_vmcli" "$fusion_vmx" ConfigParams SetEntry RemoteDisplay.vnc.port "$port" || return
    "$fusion_vmcli" "$fusion_vmx" ConfigParams SetEntry RemoteDisplay.vnc.enabled TRUE || return
    fusion_console_enabled=1
    mode=gui
  fi
  if [[ $mode == nogui ]]; then
    printf 'Open the guest console if needed: open %q\n' "$fusion_vmx"
  fi
  fusion start "$fusion_vmx" "$mode" || return
  fusion_started=1
  if (( fusion_console_enabled )); then
    python3 "$fusion_project_root/scripts/intel-macos-vm/watch-workstation-console.py" \
      "$fusion_vmcli" "$fusion_vmx" "$CODYSSEY_FUSION_VERIFY_RECOGNIZER" "$port" "$fusion_user" \
      "$fusion_bundle/.verification-console.png" &
    fusion_console_pid=$!
  fi
}

vm_running() {
  local running
  running=$(fusion list) && fusion_list_contains "$fusion_vmx" "$running"
}

fusion_guest_address() {
  local address
  if ! address=$(fusion getGuestIPAddress "$1"); then
    [[ ${CODYSSEY_FUSION_START_MODE:-gui} == nogui || ${CODYSSEY_FUSION_NAT_FALLBACK:-0} == 1 ]] || return 1
    address=$(fusion_nat_guest_address "$1" /var/db/vmware/vmnet-dhcpd-vmnet8.leases) || return
  fi
  [[ $address =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  printf '%s\n' "$address"
}

fusion_nat_guest_address() {
  local vmx=$1 leases=$2 mac now
  [[ -r $leases ]] || return 1
  mac=$(awk -F'"' '
    { key = tolower($1); sub(/[[:blank:]]*=.*$/, "", key) }
    key == "ethernet0.connectiontype" { connection = tolower($2) }
    key == "ethernet0.vnet" { network = tolower($2) }
    key == "ethernet0.generatedaddress" { mac = tolower($2) }
    END { if (connection == "nat" && (network == "" || network == "vmnet8")) print mac }
  ' "$vmx") || return
  [[ $mac =~ ^[0-9a-f]{2}(:[0-9a-f]{2}){5}$ ]] || return 1
  now=$(date -u '+%Y/%m/%d %H:%M:%S') || return
  # The DHCP file can contain multiple records for an address. Use its last
  # complete lease and reject an expired or reassigned address.
  awk -v mac="$mac" -v now="$now" '
    $1 == "lease" && $3 == "{" { ip = $2; hardware = expiry = ""; next }
    !ip { next }
    $1 == "hardware" && $2 == "ethernet" { hardware = tolower($3); sub(/;$/, "", hardware) }
    $1 == "ends" { expiry = $3 " " $4; sub(/;$/, "", expiry) }
    $1 == "}" {
      owner[ip] = hardware; expires[ip] = expiry
      if (hardware == mac) candidate = ip
      ip = ""
    }
    END {
      if (candidate && owner[candidate] == mac && expires[candidate] > now) print candidate
      else exit 1
    }
  ' "$leases"
}

vm_ready() {
  fusion_address=$(fusion_guest_address "${1:-$fusion_vmx}") || return
  fusion_console_ready
}

fusion_console_ready() {
  # The guest shell resolves its own identity and console user.
  # shellcheck disable=SC2016
  vm_exec /bin/sh -c 'test "$(id -u)" != 0 && test "$(id -un)" = "$(stat -f %Su /dev/console)"'
}

fusion_ssh() {
  local arg command='' separator='' quote_escape="'\\''"
  local -a identity_options
  identity_options=()
  if [[ -n ${CODYSSEY_FUSION_IDENTITY:-} ]]; then
    identity_options=(-o IdentitiesOnly=yes -i "$CODYSSEY_FUSION_IDENTITY")
  fi
  for arg in "$@"; do
    # SSH joins arguments into a remote shell command. Preserve argument boundaries.
    command+="$separator'${arg//\'/$quote_escape}'"
    separator=' '
  done
  ssh -F /dev/null "${fusion_ssh_terminal:--T}" -4 -o BatchMode=yes -o ConnectTimeout=5 \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null \
    -o "UserKnownHostsFile=\"$fusion_known_hosts\"" -o HostKeyAlias=codyssey-fusion \
    ${identity_options[@]+"${identity_options[@]}"} -l "$fusion_user" -- "$fusion_address" "$command"
}

vm_exec() { fusion_ssh "$@" </dev/null; }
vm_transfer() { fusion_ssh /usr/bin/tar -xf - -C "$1" <"$2"; }

vm_desktop_exec() {
  local guest_files=$1
  shift
  vm_exec /usr/bin/python3 "$guest_files/scripts/vm-aqua-exec.py" "$@"
}

fusion_request_stop() {
  local vmx=$1 mode=$2 timeout=$3
  # A guest dialog can block the vmrun RPC before it returns a stop result.
  if [[ -x /usr/bin/perl ]]; then
    /usr/bin/perl -e 'alarm shift; exec @ARGV or die "$!\n";' "$timeout" "$fusion_vmrun" -T fusion stop "$vmx" "$mode"
    return
  fi
  python3 -c '
import subprocess
import sys

timeout, *command = sys.argv[1:]
try:
    result = subprocess.run(command, timeout=float(timeout))
except subprocess.TimeoutExpired:
    print(f"Timed out waiting for Fusion to acknowledge shutdown ({timeout}s).", file=sys.stderr)
    sys.exit(124)
except OSError as error:
    sys.exit(f"Could not request Fusion shutdown: {error}")
sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
' "$timeout" "$fusion_vmrun" -T fusion stop "$vmx" "$mode"
}

vm_stop() {
  local running deadline vmx=${1:-$fusion_vmx} mode=${2:-soft}
  if [[ -n ${fusion_console_pid:-} ]]; then
    kill "$fusion_console_pid" 2>/dev/null || :
    wait "$fusion_console_pid" 2>/dev/null || :
    fusion_console_pid=
    rm -f -- "$fusion_bundle/.verification-console.png"
  fi
  running=$(fusion list) || return
  if ! fusion_list_contains "$vmx" "$running"; then
    # Without a soft stop response, disappearance from the running list
    # cannot distinguish a clean shutdown from suspension or a crash.
    if [[ $fusion_started == 0 ]]; then
      if (( ${fusion_console_enabled:-0} )); then
        "$fusion_vmcli" "$vmx" ConfigParams SetEntry RemoteDisplay.vnc.enabled FALSE || return
      fi
      return 0
    fi
    return 1
  fi
  fusion_request_stop "$vmx" "$mode" 60 || return
  deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    running=$(fusion list) || return
    if ! fusion_list_contains "$vmx" "$running"; then
      if (( ${fusion_console_enabled:-0} )); then
        "$fusion_vmcli" "$vmx" ConfigParams SetEntry RemoteDisplay.vnc.enabled FALSE || return
      fi
      return 0
    fi
    sleep 2
  done
  return 1
}

vm_stop_disposable() {
  local vmx=$1 running
  if vm_stop "$vmx"; then
    return 0
  fi
  running=$(fusion list) || return
  if fusion_list_contains "$vmx" "$running"; then
    printf 'Forcing shutdown of the disposable VM after a failed soft stop.\n' >&2
    vm_stop "$vmx" hard
  fi
}

vm_delete() {
  fusion deleteVM "$fusion_vmx" || return
  if [[ -d $fusion_bundle ]]; then
    if ! rmdir "$fusion_bundle"; then
      printf 'Fusion removed the VM but left files in %s.\n' "$fusion_bundle" >&2
      return 1
    fi
  fi
}
vm_recovery() {
  printf 'Fusion clone: %s\n' "$fusion_vmx" >&2
}
vm_retained() {
  if [[ $fusion_isolated == 1 ]]; then
    printf 'Open: open %q\n' "$fusion_vmx"
  else
    printf 'Offline clone retained for inspection: %s\n' "$fusion_vmx"
  fi
  printf 'Delete: %q -T fusion deleteVM %q\n' "$fusion_vmrun" "$fusion_vmx"
}
