#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  printf 'Usage: bash scripts/create-preinstalled-macos-image.sh --image SOURCE --name NAME\nClones a stopped Tart VM, installs OrbStack and Gureum without onboarding, then stops and retains the new base.\n'
  exit 0
fi
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
exec bash "$root/scripts/create-macos-vm.sh" --build-preinstalled "$@"
