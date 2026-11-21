#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/vm-guest-path.sh"
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  printf 'Install Command Line Tools from the guest Terminal with xcode-select --install, then retry.\n' >&2
  exit 1
fi
guest_tools_ready() {
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' &&
    node -e '
      const [major, minor] = process.versions.node.split(".").map(Number);
      process.exit(major < 22 || (major === 22 && minor < 18) ? 1 : 0);
    '
}
if ! guest_tools_ready; then
  command -v port >/dev/null || {
    printf 'Install the MacPorts package for this macOS version in the guest, then retry.\n' >&2
    exit 1
  }
  sudo "$(command -v port)" install python313 nodejs24
  sudo "$(command -v port)" select --set python3 python313
  guest_tools_ready || { printf 'Expected Python 3.10+ and Node.js 22.18+ on the guest PATH.\n' >&2; exit 1; }
fi
[[ -d '/Applications/Google Chrome.app' || -d "$HOME/Applications/Google Chrome.app" ]] || {
  printf 'Install Google Chrome in the guest, then retry.\n' >&2
  exit 1
}
