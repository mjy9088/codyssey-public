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
bash "$scripts/verify-intel-macos.sh" "$base" --prepare
fusion_started=1
vm_stop "$base"
if grep -qiE '^sata0:2\.fileName[[:blank:]]*=[[:blank:]]*"(.*/)?darwin\.iso"[[:blank:]]*$' "$base"; then
  fusion_disconnect_media "$base" sata0:2
fi
fusion_remember_base "$base"
printf 'Base is ready and stopped: %s\n' "$base"
