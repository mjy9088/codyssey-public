#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: bash %s [VERSION | --list | --app INSTALLER.app | --set-storage DIRECTORY]\n' "$0"
}
[[ ${1:-} != --help ]] || { usage; exit 0; }
scripts=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
# shellcheck source=scripts/vm-fusion.sh
. "$scripts/vm-fusion.sh"
fusion_require_intel
if [[ ${1:-} == --set-storage ]]; then
  [[ $# == 2 ]] || { usage >&2; exit 2; }
  fusion_select_storage "$2"
  exit
fi
app='/Applications/Install macOS Sequoia.app'
version=15.8.3
case ${1:-} in
  --list)
    [[ $# == 1 ]] || { usage >&2; exit 2; }
    exec softwareupdate --list-full-installers
    ;;
  --app)
    [[ $# == 2 && $2 == *.app ]] || { usage >&2; exit 2; }
    storage=$(fusion_storage_path)
    iso="$storage/installers/Sequoia-local.iso"
    bash "$scripts/create-fusion-installer.sh" "$2" "$iso"
    fusion_remember_media "$iso"
    exit
    ;;
  '')
    [[ $# == 0 ]] || { usage >&2; exit 2; }
    ;;
  *)
    [[ $# == 1 && $1 =~ ^15\.[0-9]+(\.[0-9]+)?$ ]] || { usage >&2; exit 2; }
    version=$1
    ;;
esac

storage=$(fusion_storage_path)
iso="$storage/installers/Sequoia-$version.iso"
if [[ -s $iso && -f $iso && ! -L $iso ]]; then
  fusion_remember_media "$iso"
  printf 'Existing installer: %s\n' "$iso"
  exit 0
fi
if ! softwareupdate --fetch-full-installer --full-installer-version "$version"; then
  printf 'Could not fetch Sequoia %s. Retry, use --list, or supply a full installer with --app.\n' "$version" >&2
  exit 1
fi
bash "$scripts/create-fusion-installer.sh" "$app" "$iso"
fusion_remember_media "$iso"
