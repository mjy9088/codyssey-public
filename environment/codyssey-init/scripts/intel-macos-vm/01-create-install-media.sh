#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: bash %s [VERSION | --list | --app INSTALLER.app | --set-storage DIRECTORY]\n' "$0"
}
[[ ${1:-} != --help ]] || { usage; exit 0; }
scripts=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
# shellcheck source=scripts/vm-fusion.sh
. "$scripts/vm-fusion.sh"
. "$scripts/vm-progress.sh"
fusion_require_intel
if [[ ${1:-} == --set-storage ]]; then
  [[ $# == 2 ]] || { usage >&2; exit 2; }
  fusion_select_storage "$2"
  exit
fi
app='/Applications/Install macOS Sequoia.app'
version=15.8.3
quit_installer() {
  [[ -d $1 ]] || return 0
  if ! /usr/bin/osascript -l JavaScript "$scripts/intel-macos-vm/quit-installer.js" "$1"; then
    printf 'If the host macOS installer is still open, quit it with Command-Q.\n' >&2
  fi
}
case ${1:-} in
  --list)
    [[ $# == 1 ]] || { usage >&2; exit 2; }
    vm_progress "Checking available macOS installers" softwareupdate --list-full-installers
    exit
    ;;
  --app)
    [[ $# == 2 && $2 == *.app ]] || { usage >&2; exit 2; }
    storage=$(fusion_storage_path)
    iso="$storage/installers/Sequoia-local.iso"
    quit_installer "$2"
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
  quit_installer "$app"
  fusion_remember_media "$iso"
  printf 'Existing installer: %s\n' "$iso"
  exit 0
fi
printf 'Fetching macOS Sequoia %s from Apple.\n' "$version"
if ! softwareupdate --fetch-full-installer --full-installer-version "$version"; then
  quit_installer "$app"
  printf 'Could not fetch Sequoia %s. Retry, use --list, or supply a full installer with --app.\n' "$version" >&2
  exit 1
fi
quit_installer "$app"
bash "$scripts/create-fusion-installer.sh" "$app" "$iso"
fusion_remember_media "$iso"
