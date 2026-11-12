#!/usr/bin/env bash
# Update both managed blocks as one atomic file replacement.
set -euo pipefail
zsh_dir=${ZDOTDIR:-$HOME}
mkdir -p "$zsh_dir"
zshrc="$zsh_dir/.zshrc"
# Preserve a user's symlink rather than replacing it with a regular file.
for ((depth=0; depth<40; depth++)); do
  [[ -L $zshrc ]] || break
  link=$(readlink "$zshrc")
  case $link in /*) zshrc=$link ;; *) zshrc="$(dirname -- "$zshrc")/$link" ;; esac
done
[[ ! -L $zshrc ]] || { printf 'Cannot resolve .zshrc symlink.\n' >&2; exit 1; }
temporary=$(mktemp "$(dirname -- "$zshrc")/.codyssey-zshrc.XXXXXX")
trap 'rm -f "$temporary"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -e $zshrc ]]; then cp -p "$zshrc" "$temporary"; fi
if ! grep -q '^# codyssey-init: OrbStack tools$' "$temporary"; then
  cat >>"$temporary" <<'BLOCK'

# codyssey-init: OrbStack tools
for codyssey_orb_app in /Applications/OrbStack.app "$HOME/Applications/OrbStack.app"; do
  if [ -x "$codyssey_orb_app/Contents/MacOS/xbin/docker" ]; then
    export PATH="$PATH:$codyssey_orb_app/Contents/MacOS/xbin"
    break
  fi
done
unset codyssey_orb_app
BLOCK
fi
if ! grep -q '^# codyssey-init: mise$' "$temporary"; then
  cat >>"$temporary" <<'BLOCK'

# codyssey-init: mise
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
eval "$(mise activate zsh)"
BLOCK
fi
mv -f "$temporary" "$zshrc"
