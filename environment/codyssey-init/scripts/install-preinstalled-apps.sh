#!/usr/bin/env bash
# Only run in a newly cloned disposable image; do not start either application.
set -euo pipefail
umask 077
[[ ${1:-} == --disposable && $# == 1 && $(uname -s) == Darwin && $(id -u) != 0 ]] || {
  printf 'Use --disposable as the macOS guest desktop user.\n' >&2; exit 1;
}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/lib/preparation.sh"
# Pinned OrbStack 2.2.4 checksums from Homebrew's official orbstack cask.
# https://github.com/Homebrew/homebrew-cask/blob/master/Casks/o/orbstack.rb
case $(uname -m) in
  arm64) arch=arm64; sha=f0c698e709c99fb3ee87f92c3a0445c6b8f5a10d6a0edd4f4d461925d194b86a ;;
  x86_64) arch=amd64; sha=b18b397aff7e81ab7d63934a569da659ec73b0a19a99fa7521d4b75c96db5544 ;;
  *) printf 'Unsupported OrbStack architecture.\n' >&2; exit 1 ;;
esac
# A cloned verification image may contain a stopped Colima installation. Do not
# uninstall its packages or delete disks; detach its user-owned CLI links only.
if command -v colima >/dev/null && colima status --profile codyssey-verify >/dev/null 2>&1; then
  run_quiet_step 'Stopping cloned Colima' colima stop --profile codyssey-verify
fi
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  printf 'Stop the cloned Docker engine before preparing the image.\n' >&2; exit 1
fi
if command -v brew >/dev/null; then
  for package in docker docker-compose docker-buildx; do
    if brew list --formula "$package" >/dev/null 2>&1; then
      run_quiet_step 'Unlinking cloned Docker CLI' brew unlink "$package"
    fi
  done
fi
# Remove only the bootstrap-owned OrbStack PATH block in this disposable clone.
# A retained private backup makes that transformation inspectable.
python3 - <<'PYTHON'
import os
from pathlib import Path
path = Path.home() / ".zshrc"
if path.exists():
    text = path.read_text()
    marker = "# codyssey-init: OrbStack tools\n"
    if marker in text:
        start = text.index(marker)
        end = text.find("unset codyssey_orb_app\n", start)
        if end < 0:
            raise SystemExit("Unrecognized owned OrbStack PATH block; choose a clean base")
        backup = Path.home() / "Library/Application Support/codyssey-init/image-zshrc.backup"
        backup.parent.mkdir(parents=True, exist_ok=True)
        with backup.open("x") as stream:
            stream.write(text)
        backup.chmod(0o600)
        path.write_text(text[:start] + text[end + len("unset codyssey_orb_app\n"):])
PYTHON
stage=$(mktemp -d)
mount="$stage/mount"
mounted=0
cleanup() {
  status=$?
  trap - EXIT
  if (( mounted )) && ! hdiutil detach "$mount" -quiet; then
    printf 'Could not detach OrbStack disk image; staging retained at %s\n' "$stage" >&2
    (( status != 0 )) || status=1
  else
    rm -rf "$stage"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Installing applications without starting onboarding…\n'
curl --fail --location --silent --show-error --retry 3 \
  "https://cdn-updates.orbstack.dev/$arch/OrbStack_v2.2.4_21120_$arch.dmg" -o "$stage/orbstack.dmg"
[[ $(shasum -a 256 "$stage/orbstack.dmg" | cut -d ' ' -f 1) == "$sha" ]] || {
  printf 'OrbStack archive checksum mismatch.\n' >&2; exit 1;
}
mkdir -p "$mount" "$HOME/Applications"
hdiutil attach "$stage/orbstack.dmg" -mountpoint "$mount" -nobrowse -readonly -quiet
mounted=1
app="$HOME/Applications/OrbStack.app"
[[ ! -e $app ]] || { printf 'Refusing to replace an existing per-user OrbStack app.\n' >&2; exit 1; }
ditto "$mount/OrbStack.app" "$app"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist") == 2.2.4 ]]
[[ -x $app/Contents/MacOS/bin/orb && -x $app/Contents/MacOS/xbin/docker ]]
run_quiet_step 'Installing Gureum' bash "$root/scripts/install-gureum.sh"
[[ -d '/Applications/Google Chrome.app' || -d "$HOME/Applications/Google Chrome.app" ]] || {
  printf 'Use a base with Chrome preinstalled.\n' >&2; exit 1;
}
# Validate the login shell too: a stale PATH must not turn this into a warm image.
if /bin/zsh -ic 'command -v docker' >/dev/null 2>&1; then
  printf 'Docker is still on the login PATH. Choose a clean base or remove its Docker PATH customization in this clone.\n' >&2
  exit 1
fi
printf 'READY: OrbStack 2.2.4 and Gureum 1.13.2 installed; Docker CLI unavailable; input activation untouched.\n'
