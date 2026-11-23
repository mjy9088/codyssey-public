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
. "$root/scripts/vm-progress.sh"

install_command_line_tools() (
  request=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  if (set -C; : > "$request") 2>/dev/null; then
    trap 'rm -f -- "$request"' EXIT
  fi
  listing=$(LC_ALL=C vm_progress "Checking Apple Software Update for Command Line Tools" /usr/sbin/softwareupdate --list) || return 1
  label=$(awk '/^[[:space:]]*\* Label: Command Line Tools for Xcode/ {
    sub(/^[[:space:]]*\* Label: /, ""); print
  }' <<< "$listing" | sort -V | tail -n 1)
  [[ -n $label ]] || { printf 'Apple Software Update did not offer Command Line Tools.\n' >&2; return 1; }
  vm_progress "Installing $label from Apple Software Update" admin /usr/sbin/softwareupdate --install "$label" &&
    admin /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
)

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  if (( ! use_credential )) || ! install_command_line_tools; then
    printf 'Install Command Line Tools from the guest Terminal with xcode-select --install, then retry.\n' >&2
    exit 1
  fi
fi
if ! vm_guest_python_ready; then
  printf 'Installing Python 3.14.10 from the official macOS package.\n'
  (
    work=$(mktemp -d)
    trap 'rm -rf -- "$work"' EXIT
    package="$work/Python.pkg"
    curl --fail --show-error --location --retry 2 --proto '=https' --proto-redir '=https' \
      https://www.python.org/ftp/python/3.14.10/python-3.14.10-macos11.pkg -o "$package"
    digest=$(shasum -a 256 "$package")
    [[ ${digest%% *} == 286c7018aa2730f6747ca433dccdc2b31be45f078a9ea0ffa44d5f06368fd2d7 ]] || {
      printf 'Python package checksum mismatch.\n' >&2
      exit 1
    }
    # Keep the framework and /usr/local/bin tools required by the guest harness.
    {
      printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><array>'
      for component in Applications Documentation ProfileChanges InstallPip TFramework; do
        printf '%s\n' '<dict>' \
          "<key>choiceIdentifier</key><string>org.python.Python.Python$component-3.14</string>" \
          '<key>choiceAttribute</key><string>selected</string>' \
          '<key>attributeSetting</key><integer>0</integer>' '</dict>'
      done
      printf '%s\n' '</array></plist>'
    } > "$work/choices.plist"
    vm_progress "Installing the Python package" admin /usr/sbin/installer -pkg "$package" -target / -applyChoiceChangesXML "$work/choices.plist"
  )
  hash -r
  vm_guest_python_ready || { printf 'Expected Python 3.10+ on the guest PATH.\n' >&2; exit 1; }
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
    curl --fail --show-error --location --retry 2 --proto '=https' --proto-redir '=https' \
      https://dl.google.com/chrome/mac/universal/stable/CHFA/googlechrome.dmg -o "$work/chrome.dmg"
    hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$work/chrome.dmg" >/dev/null
    attached=1
    # Google's stable bundle identifier and Apple-issued Developer ID team.
    vm_progress "Checking the Google Chrome signature" codesign --verify --deep --strict \
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

vm_progress "Preparing OrbStack" bash "$root/scripts/install-orbstack.sh"
vm_progress "Preparing Gureum" bash "$root/scripts/install-gureum.sh"
vm_progress "Preparing iTerm2" bash "$root/scripts/install-iterm2.sh"
