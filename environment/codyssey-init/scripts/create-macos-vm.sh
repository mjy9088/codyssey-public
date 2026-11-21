#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/create-macos-vm.sh --image SOURCE [--name NAME] [--delete-on-success] [--workstation | --preinstalled]
Apple Silicon: Tart on macOS 14+, with mise and a desktop running Guest Agent.
SOURCE is a reviewed local Tart base or a registry image pinned with @sha256:...
Intel: Fusion Pro with VMware Tools and key-authenticated SSH in the guest.
SOURCE is a reviewed local .vmx. Set CODYSSEY_FUSION_GUEST_USER and
CODYSSEY_FUSION_KNOWN_HOSTS (pin the base key under codyssey-fusion).
The clone's .vmwarevm bundle is created in the current directory.
Provisioning uses Homebrew or preinstalled Intel tools. --preinstalled checks installed apps and cold-start fixtures
before using software-emulated Docker; the OrbStack engine is never required.
--workstation runs the live macOS setup and preferences checks without Docker.
Creates, provisions, and verifies a fresh VM.
Retains the VM on failure and stops it after confirmed guest cleanup.
No host home directory is shared.
EOF
}
image='' name="codyssey-verify-$(date +%Y%m%d-%H%M%S)-$$" delete_on_success=0 preinstalled=0 build_preinstalled=0 workstation=0
while (( $# )); do
  case $1 in
    --help) usage; exit 0 ;;
    --image|--name)
      [[ $# -ge 2 && -n $2 ]] || { usage >&2; exit 1; }
      if [[ $1 == --image ]]; then image=$2; else name=$2; fi
      shift 2 ;;
    --build-preinstalled) build_preinstalled=1; shift ;;
    --preinstalled) preinstalled=1; shift ;;
    --workstation) workstation=1; shift ;;
    --delete-on-success) delete_on_success=1; shift ;;
    *) usage >&2; exit 1 ;;
  esac
done
(( !build_preinstalled || !delete_on_success )) || { printf "A base image cannot be deleted on success.\n" >&2; exit 1; }
(( !workstation || !(preinstalled || build_preinstalled) )) || { usage >&2; exit 1; }
[[ -n $image && $image != -* && $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { usage >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || { printf 'This verifier requires a macOS host.\n' >&2; exit 1; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
# The selected adapter owns its VM handle and guest transport.
case $(uname -m) in
  arm64)
    backend_label=Tart
    . "$root/scripts/vm-tart.sh"
    ;;
  x86_64)
    backend_label=Fusion
    . "$root/scripts/vm-fusion.sh"
    ;;
  *) printf 'Unsupported Mac architecture.\n' >&2; exit 1 ;;
esac
vm_init "$image" "$name" "$root"
. "$root/scripts/vm-files.sh"
. "$root/lib/preparation.sh"
created=0 prepare_requested=0 transfer='' cleaned=0
cleanup() {
  result=$1 cleanup_result=0 stop_confirmed=1
  (( cleaned == 0 )) || return "$result"
  cleaned=1
  trap - EXIT
  [[ -z $transfer ]] || rm -f "$transfer"
  if (( created )); then
    # Flush the nested Linux disk before stopping macOS; otherwise removed
    # containers can reappear when a retained VM is booted or cloned.
    if (( prepare_requested )) && ! run_quiet_step 'Stopping test Docker' vm_exec /bin/bash "$guest_root/scripts/prepare-macos-vm.sh" --disposable --stop; then
      printf 'VM %s retained without requesting shutdown. Could not confirm guest Docker stopped.\n' "$name" >&2
      vm_recovery
      (( result == 0 )) && return 1
      return "$result"
    fi
    if ! vm_stop; then
      printf 'Could not confirm that %s stopped VM %s.\n' "$backend_label" "$name" >&2
      cleanup_result=1
      stop_confirmed=0
    fi
    if (( result == 0 && cleanup_result == 0 && delete_on_success )); then
      if ! vm_delete; then
        printf 'Could not complete deletion of VM %s.\n' "$name" >&2
        cleanup_result=1
      fi
    elif (( stop_confirmed )); then
      printf 'VM retained (stopped): %s\n' "$name"
      vm_retained
    else
      printf 'VM retained; stop was not confirmed: %s\n' "$name"
    fi
  fi
  (( result != 0 )) && return "$result"
  return "$cleanup_result"
}
finish() {
  result=$?
  if cleanup "$result"; then
    exit 0
  else
    exit $?
  fi
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Backends refuse an existing destination. Cleanup owns only a successful clone.
vm_clone
created=1
vm_start
ready=0
deadline=$((SECONDS + 360))
while (( SECONDS < deadline )); do
  vm_running || { printf '%s exited before guest readiness.\n' "$backend_label" >&2; exit 1; }
  if vm_ready 2>/dev/null; then ready=1; break; fi
  sleep 2
done
(( ready )) || { printf '%s guest connection did not become ready within six minutes.\n' "$backend_label" >&2; exit 1; }
guest_root=$(vm_exec /bin/sh -c 'mktemp -d "$HOME/codyssey-vm-verification.XXXXXX"')
[[ $guest_root == /* && $guest_root != *$'\n'* ]] || { printf 'Invalid guest working directory.\n' >&2; exit 1; }
transfer=$(mktemp)
chmod 0600 "$transfer"
tar -C "$root" -cf "$transfer" "${vm_files[@]}"
vm_transfer "$guest_root" "$transfer"
rm -f "$transfer"
transfer=
if (( build_preinstalled )); then
  vm_exec /bin/bash "$guest_root/scripts/install-preinstalled-apps.sh" --disposable
elif (( workstation )); then
  vm_desktop_exec "$guest_root" 1200 /bin/bash "$guest_root/scripts/verify-macos-vm.sh" --disposable --workstation
else
  if (( preinstalled )); then
    vm_exec /usr/bin/python3 "$guest_root/scripts/check-preinstalled-apps.py"
    vm_exec /usr/bin/python3 "$guest_root/tests/preinstalled-tools-test.py"
  fi
  prepare_requested=1
  vm_exec /bin/bash "$guest_root/scripts/prepare-macos-vm.sh" --disposable --managed
  vm_desktop_exec "$guest_root" 21600 /usr/bin/env DOCKER_CONTEXT=colima-codyssey-verify \
    /bin/bash "$guest_root/scripts/verify-macos-vm.sh" --disposable
fi
if cleanup 0; then
  :
else
  exit $?
fi
if (( build_preinstalled )); then
  printf 'READY: stopped preinstalled base %s (OrbStack engine not exercised).\n' "$name"
else
  printf 'PASS: fresh macOS VM %s completed environment verification.\n' "$name"
fi
