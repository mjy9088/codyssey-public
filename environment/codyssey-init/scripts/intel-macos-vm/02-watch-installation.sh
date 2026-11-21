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
command -v uv >/dev/null || { printf 'Install uv to use the installer watcher.\n' >&2; exit 1; }
storage=$(fusion_storage_path)
umask 077
mkdir -p "$storage/runs"
run=$(mktemp -d "$storage/runs/watch.XXXXXX")
printf 'Installer screenshots and status: %s\n' "$run"
exec uv run --no-build "$scripts/watch-fusion-installer.py" \
  --fusion-library "${fusion_vmrun%/*}" --vmx "$base" --output-dir "$run" \
  --monitor --interval 180 --timeout 14400
