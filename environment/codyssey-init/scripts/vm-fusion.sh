#!/usr/bin/env bash
# Fusion owns the VMX lifecycle. VMware Tools supplies the address; SSH
# supplies command status, output, and archive input without guest passwords.
vm_init() {
  local image=$1 name=$2
  fusion_isolated=0 fusion_started=0
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
  [[ $image == *.vmx && -f $image && ! -L $image && $image != *$'\n'* ]] || {
    printf 'Fusion requires a reviewed, powered-off local .vmx.\n' >&2
    return 1
  }
  fusion_source=$(CDPATH='' cd -- "$(dirname -- "$image")" && pwd -P)/$(basename -- "$image")
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

vm_clone() {
  local running
  running=$(fusion list) || return
  if fusion_list_contains "$fusion_source" "$running"; then
    printf 'Shut down the Fusion base VM before cloning.\n' >&2
    return 1
  fi
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
  fusion_address=$(fusion getGuestIPAddress "$fusion_vmx") || return
  [[ $fusion_address =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  vm_exec /bin/sh -c 'test "$(id -u)" != 0 && test "$(id -un)" = "$(stat -f %Su /dev/console)"'
}

fusion_ssh() {
  local arg command='' separator='' quote_escape="'\\''"
  for arg in "$@"; do
    # SSH joins arguments into a remote shell command. Preserve argument boundaries.
    command+="$separator'${arg//\'/$quote_escape}'"
    separator=' '
  done
  ssh -F /dev/null -T -4 -o BatchMode=yes -o ConnectTimeout=5 \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null \
    -o "UserKnownHostsFile=\"$fusion_known_hosts\"" -o HostKeyAlias=codyssey-fusion \
    -l "$fusion_user" -- "$fusion_address" "$command"
}

vm_exec() { fusion_ssh "$@" </dev/null; }
vm_transfer() { fusion_ssh /usr/bin/tar -xf - -C "$1" <"$2"; }

vm_desktop_preflight() {
  vm_desktop_exec "$1" 60 /usr/bin/swift "$1/scripts/verify-dock-ui.swift" --preflight
}

vm_desktop_exec() {
  local guest_files=$1
  shift
  vm_exec /usr/bin/python3 "$guest_files/scripts/vm-aqua-exec.py" "$@"
}

vm_stop() {
  local running deadline
  running=$(fusion list) || return
  if ! fusion_list_contains "$fusion_vmx" "$running"; then
    # Without a soft stop response, disappearance from the running list
    # cannot distinguish a clean shutdown from suspension or a crash.
    [[ $fusion_started == 0 ]]
    return
  fi
  fusion stop "$fusion_vmx" soft || return
  deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    running=$(fusion list) || return
    if ! fusion_list_contains "$fusion_vmx" "$running"; then
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
