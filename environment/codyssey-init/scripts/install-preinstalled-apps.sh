#!/usr/bin/env bash
# Only run in a newly cloned disposable image; do not start either application.
set -euo pipefail
umask 077
[[ ${1:-} == --disposable && $# == 1 && $(uname -s) == Darwin && $(id -u) != 0 ]] || {
  printf 'Use --disposable as the macOS guest desktop user.\n' >&2; exit 1;
}
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/lib/preparation.sh"
. "$root/scripts/vm-guest-path.sh"
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
run_quiet_step 'Installing OrbStack' bash "$root/scripts/install-orbstack.sh"
run_quiet_step 'Installing iTerm2' bash "$root/scripts/install-iterm2.sh"
run_quiet_step 'Configuring iTerm2 keyboard' bash "$root/scripts/configure-iterm2.sh"
run_quiet_step 'Installing Gureum' bash "$root/scripts/install-gureum.sh"
[[ -d '/Applications/Google Chrome.app' || -d "$HOME/Applications/Google Chrome.app" ]] || {
  printf 'Use a base with Chrome preinstalled.\n' >&2; exit 1;
}
# Validate the login shell too: a stale PATH must not turn this into a warm image.
if /bin/zsh -ic 'command -v docker' >/dev/null 2>&1; then
  printf 'Docker is still on the login PATH. Choose a clean base or remove its Docker PATH customization in this clone.\n' >&2
  exit 1
fi
printf 'READY: OrbStack, Gureum and iTerm2 available; Docker CLI unavailable; input activation untouched.\n'
