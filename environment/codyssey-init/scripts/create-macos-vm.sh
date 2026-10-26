#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/create-macos-vm.sh --image SOURCE [--name NAME] [--delete-on-success] [--preinstalled]
SOURCE: reviewed local Tart base VM or registry image pinned with @sha256:...
Requires Apple Silicon macOS 14+, mise, and a logged-in desktop with Guest Agent.
Installs the pinned Tart from mise.vm.toml on demand; no global Tart setup is needed.
Provisioning needs Homebrew. --preinstalled checks installed apps and cold-start fixtures
before using software-emulated Docker; the OrbStack engine is never required.
Creates, provisions, and verifies a fresh VM.
Stops and retains the VM on failure. No host home directory is shared.
EOF
}
image= name="codyssey-verify-$(date +%Y%m%d-%H%M%S)-$$" delete_on_success=0 preinstalled=0 build_preinstalled=0
while (( $# )); do
  case $1 in
    --help) usage; exit 0 ;;
    --image|--name)
      [[ $# -ge 2 && -n $2 ]] || { usage >&2; exit 1; }
      if [[ $1 == --image ]]; then image=$2; else name=$2; fi
      shift 2 ;;
    --build-preinstalled) build_preinstalled=1; shift ;;
    --preinstalled) preinstalled=1; shift ;;
    --delete-on-success) delete_on_success=1; shift ;;
    *) usage >&2; exit 1 ;;
  esac
done
(( !build_preinstalled || !delete_on_success )) || { printf "A base image cannot be deleted on success.\n" >&2; exit 1; }
[[ -n $image && $image != -* && $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { usage >&2; exit 1; }
if [[ $image == */* && ! $image =~ @sha256:[0-9a-f]{64}$ ]]; then
  printf 'Registry VM images must be pinned with @sha256:<64 lowercase hex digits>.\n' >&2; exit 1
fi
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { printf 'Tart requires an Apple Silicon Mac.\n' >&2; exit 1; }
[[ $(sw_vers -productVersion | cut -d . -f 1) -ge 14 ]] || { printf 'tart exec requires macOS 14+.\n' >&2; exit 1; }
command -v mise >/dev/null || { printf 'Install mise on the host first.\n' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
# Name only Tart so unrelated configured tools are not installed. An explicit
# install also works when mise's automatic installation setting is disabled.
MISE_QUIET=1 mise -C "$root" -E vm install tart
tart() { MISE_QUIET=1 mise -C "$root" -E vm exec tart -- tart "$@"; }
tart --version >/dev/null
. "$root/scripts/vm-files.sh"
. "$root/lib/preparation.sh"
export TART_NO_AUTO_PRUNE=1
created=0 prepared=0 runner= transfer= cleaned=0
cleanup() {
  result=$1 cleanup_result=0 stop_confirmed=1
  (( cleaned == 0 )) || return "$result"
  cleaned=1
  trap - EXIT
  [[ -z $transfer ]] || rm -f "$transfer"
  if (( created )); then
    # Flush the nested Linux disk before stopping macOS; otherwise removed
    # containers can reappear when a retained VM is booted or cloned.
    if (( prepared )) && ! run_quiet_step 'Stopping test Docker' tart exec "$name" /opt/homebrew/bin/colima stop --profile codyssey-verify; then
      printf 'Could not cleanly stop the guest Docker VM.\n' >&2
      cleanup_result=1
    fi
    if ! tart stop "$name"; then
      printf 'Could not confirm that Tart stopped VM %s.\n' "$name" >&2
      cleanup_result=1
      stop_confirmed=0
    fi
    if [[ -n $runner ]]; then
      kill "$runner" 2>/dev/null || true
      wait "$runner" 2>/dev/null || true
    fi
    if (( result == 0 && cleanup_result == 0 && delete_on_success )); then
      if ! tart delete "$name"; then
        printf 'Could not delete stopped VM %s.\n' "$name" >&2
        cleanup_result=1
        printf 'VM retained (stopped): %s\n' "$name"
      fi
    elif (( stop_confirmed )); then
      printf 'VM retained (stopped): %s\n' "$name"
      printf 'Open: mise -C %q -E vm exec tart -- tart run %q\n' "$root" "$name"
      printf 'Delete: mise -C %q -E vm exec tart -- tart delete %q\n' "$root" "$name"
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
# clone refuses an existing name; ownership starts only after it succeeds.
tart clone "$image" "$name"
created=1
tart set "$name" --cpu 4 --memory 8192
MISE_QUIET=1 mise -C "$root" -E vm exec tart -- tart run --no-graphics "$name" &
runner=$!
ready=0
deadline=$((SECONDS + 360))
while (( SECONDS < deadline )); do
  kill -0 "$runner" 2>/dev/null || { printf 'Tart exited before guest readiness.\n' >&2; exit 1; }
  if tart exec "$name" /usr/bin/true 2>/dev/null; then ready=1; break; fi
  sleep 2
done
(( ready )) || { printf 'Guest Agent did not become ready within six minutes.\n' >&2; exit 1; }
guest_root=$(tart exec "$name" /bin/sh -c 'mktemp -d "$HOME/codyssey-vm-verification.XXXXXX"')
[[ $guest_root == /* && $guest_root != *$'\n'* ]] || { printf 'Invalid guest working directory.\n' >&2; exit 1; }
transfer=$(mktemp)
chmod 0600 "$transfer"
tar -C "$root" -cf "$transfer" "${vm_files[@]}"
tart exec -i "$name" /usr/bin/tar -xf - -C "$guest_root" <"$transfer"
rm -f "$transfer"
transfer=
if (( build_preinstalled )); then
  tart exec "$name" /bin/bash "$guest_root/scripts/install-preinstalled-apps.sh" --disposable
else
  if (( preinstalled )); then
    tart exec "$name" /usr/bin/python3 "$guest_root/scripts/check-preinstalled-apps.py"
    tart exec "$name" /usr/bin/python3 "$guest_root/tests/preinstalled-tools-test.py"
  fi
  tart exec "$name" /bin/bash "$guest_root/scripts/prepare-macos-vm.sh" --disposable
  prepared=1
  tart exec "$name" /usr/bin/env DOCKER_CONTEXT=colima-codyssey-verify \
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
