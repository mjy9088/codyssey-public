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
base=$(fusion_selected_base "${1:-}")
if [[ -z ${CODYSSEY_FUSION_VERIFY_RECOGNIZER:-} ]]; then
  . "$scripts/vm-progress.sh"
  work=$(mktemp -d)
  opened_fusion=0
  if ! pgrep -x 'VMware Fusion' >/dev/null; then opened_fusion=1; fi
  cleanup() {
    rm -rf -- "$work"
    if (( opened_fusion )); then
      bash "$scripts/intel-macos-vm/07-close-fusion.sh" || :
    fi
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  vm_progress "Building the Fusion console recognizer" xcrun swiftc \
    "$scripts/intel-macos-vm/recognize-screen.swift" -o "$work/recognize"
  export CODYSSEY_FUSION_VERIFY_RECOGNIZER="$work/recognize"
fi
bash "$scripts/verify-intel-macos.sh" "$base"
if (( $# )); then fusion_remember_base "$base"; fi
