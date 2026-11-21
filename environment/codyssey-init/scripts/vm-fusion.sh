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
  "$fusion_vmcli" "$fusion_vmx" ConfigParams SetEntry isolation.tools.hgfs.disable TRUE || return
  "$fusion_vmcli" "$fusion_vmx" ConfigParams SetEntry sharedFolder.maxNum 0 || return
  fusion_isolated=1
  # Start through the Fusion application so its inventory and guest transport
  # remain available for the Aqua desktop verification.
  fusion start "$fusion_vmx" gui || return
  fusion_started=1
}

vm_running() {
  local running
  running=$(fusion list) && fusion_list_contains "$fusion_vmx" "$running"
}

vm_ready() {
  fusion_address=$(fusion getGuestIPAddress "${1:-$fusion_vmx}") || return
  [[ $fusion_address =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
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

vm_stop() {
  local running deadline vmx=${1:-$fusion_vmx}
  running=$(fusion list) || return
  if ! fusion_list_contains "$vmx" "$running"; then
    # Without a soft stop response, disappearance from the running list
    # cannot distinguish a clean shutdown from suspension or a crash.
    if [[ $fusion_started == 0 ]]; then
      return 0
    fi
    return 1
  fi
  fusion stop "$vmx" soft || return
  deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    running=$(fusion list) || return
    if ! fusion_list_contains "$vmx" "$running"; then
      return 0
    fi
    sleep 2
  done
  return 1
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
