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
if [[ $# == 0 ]]; then
  exec bash "$scripts/verify-intel-macos.sh" "$base"
fi
bash "$scripts/verify-intel-macos.sh" "$base"
fusion_remember_base "$base"
