#!/usr/bin/env bash
set -euo pipefail

if (( $# )); then
  printf 'Usage: bash %s\n' "$0"
  [[ $# == 1 && $1 == --help ]]
  exit
fi

scripts=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
# shellcheck source=scripts/vm-fusion.sh
. "$scripts/vm-fusion.sh"
fusion_require_intel
if ! pgrep -x 'VMware Fusion' >/dev/null; then
  printf 'VMware Fusion is already closed.\n'
  exit 0
fi
fusion_tools
running=$(fusion list)
if [[ $running != 'Total running VMs: 0' ]]; then
  printf 'Fusion is still in use. Close the remaining guest sessions first.\n%s\n' "$running" >&2
  exit 1
fi

/usr/bin/osascript -e 'with timeout of 15 seconds' -e 'tell application id "com.vmware.fusion" to quit' -e 'end timeout'
deadline=$((SECONDS + 15))
while pgrep -x 'VMware Fusion' >/dev/null; do
  if (( SECONDS >= deadline )); then
    printf 'Fusion did not finish quitting. Check its open dialogs.\n' >&2
    exit 1
  fi
  sleep 1
done
printf 'Closed VMware Fusion.\n'
