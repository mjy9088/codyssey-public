#!/usr/bin/env bash
set -euo pipefail

use_credential=0
if [[ ${1:-} == --sudo-password-stdin ]]; then
  IFS= read -r guest_password
  [[ -n $guest_password ]]
  use_credential=1
fi

admin() {
  if (( use_credential )); then
    printf '%s\n' "$guest_password" | sudo -S -p '' "$@"
  else
    sudo "$@"
  fi
}

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/vm-guest-path.sh"

install_command_line_tools() (
  request=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  if (set -C; : > "$request") 2>/dev/null; then
    trap 'rm -f -- "$request"' EXIT
  fi
  listing=$(LC_ALL=C /usr/sbin/softwareupdate --list) || return 1
  label=$(awk '/^[[:space:]]*\* Label: Command Line Tools for Xcode/ {
    sub(/^[[:space:]]*\* Label: /, ""); print
  }' <<< "$listing" | sort -V | tail -n 1)
  [[ -n $label ]] || { printf 'Apple Software Update did not offer Command Line Tools.\n' >&2; return 1; }
  printf 'Installing %s from Apple Software Update.\n' "$label"
  admin /usr/sbin/softwareupdate --install "$label" &&
    admin /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
)

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  if (( ! use_credential )) || ! install_command_line_tools; then
    printf 'Install Command Line Tools from the guest Terminal with xcode-select --install, then retry.\n' >&2
    exit 1
  fi
fi
guest_tools_ready() {
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' &&
    node -e '
      const [major, minor] = process.versions.node.split(".").map(Number);
      process.exit(major < 22 || (major === 22 && minor < 18) ? 1 : 0);
    '
}
if ! guest_tools_ready; then
  if ! command -v port >/dev/null; then
    [[ $(sw_vers -productVersion) == 15.* ]] || {
      printf 'Install the official MacPorts package for this guest macOS version, then retry.\n' >&2
      exit 1
    }
    printf 'Installing the pinned MacPorts package for Sequoia.\n'
    (
      work=$(mktemp -d)
      trap 'rm -rf -- "$work"' EXIT
      curl --fail --silent --show-error --location --retry 2 --proto '=https' --proto-redir '=https' \
        https://distfiles.macports.org/MacPorts/MacPorts-2.12.7-15-Sequoia.pkg -o "$work/MacPorts.pkg"
      digest=$(shasum -a 256 "$work/MacPorts.pkg")
      [[ ${digest%% *} == 87b2e87ed7adc4aca947b42eb7ff991614cc0edfccb486237f2bbc75f28aae63 ]] || {
        printf 'MacPorts package checksum mismatch.\n' >&2
        exit 1
      }
      admin /usr/sbin/installer -pkg "$work/MacPorts.pkg" -target /
    )
  fi
  admin "$(command -v port)" install python313 nodejs24
  admin "$(command -v port)" select --set python3 python313
  hash -r
  guest_tools_ready || { printf 'Expected Python 3.10+ and Node.js 22.18+ on the guest PATH.\n' >&2; exit 1; }
fi
if [[ ! -d '/Applications/Google Chrome.app' && ! -d "$HOME/Applications/Google Chrome.app" ]]; then
  printf 'Downloading and verifying Google Chrome.\n'
  (
    work=$(mktemp -d)
    mount="$work/Chrome"
    attached=0
    # Invoked by the EXIT trap.
    # shellcheck disable=SC2329
    cleanup() {
      if (( attached )) && ! hdiutil detach "$mount"; then
        printf 'Chrome image is still attached: %s\n' "$work" >&2
        return
      fi
      rm -rf -- "$work"
    }
    trap cleanup EXIT
    mkdir "$mount"
    curl --fail --silent --show-error --location --retry 2 --proto '=https' --proto-redir '=https' \
      https://dl.google.com/chrome/mac/universal/stable/CHFA/googlechrome.dmg -o "$work/chrome.dmg"
    hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$work/chrome.dmg" >/dev/null
    attached=1
    # Google's stable bundle identifier and Apple-issued Developer ID team.
    codesign --verify --deep --strict \
      -R '=anchor apple generic and identifier "com.google.Chrome" and certificate leaf[subject.OU] = "EQHXZ8M8AV"' \
      "$mount/Google Chrome.app"
    mkdir -p "$HOME/Applications"
    stage=$(mktemp -d "$HOME/Applications/.codyssey-chrome.XXXXXX")
    trap 'rm -rf -- "$stage"; cleanup' EXIT
    ditto "$mount/Google Chrome.app" "$stage/Google Chrome.app"
    hdiutil detach "$mount" >/dev/null
    attached=0
    mv -n "$stage/Google Chrome.app" "$HOME/Applications/"
  )
fi
chrome='/Applications/Google Chrome.app'
[[ -d $chrome ]] || chrome="$HOME/Applications/Google Chrome.app"
[[ -x "$chrome/Contents/MacOS/Google Chrome" ]] || {
  printf 'The Google Chrome bundle needs repair: %s\n' "$chrome" >&2
  exit 1
}
