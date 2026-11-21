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
fusion_boot_target "$base"
fusion start "$base" gui
