#!/usr/bin/env bash
set -euo pipefail
die() { printf 'codyssey-init: %s\n' "$*" >&2; exit 1; }

write_shell_quoted() {
  local value=$1
  printf "'"
  while [[ $value == *"'"* ]]; do
    printf "%s'\\\\''" "${value%%\'*}"
    value=${value#*\'}
  done
  printf "%s'" "$value"
}

install_managed_j() {
  local target=$1 bin command_path first_line second_line temporary mise_path
  bin="$HOME/.local/bin"
  command_path="$bin/j"
  if [[ -e $command_path || -L $command_path ]]; then
    first_line=
    second_line=
    {
      IFS= read -r first_line || true
      IFS= read -r second_line || true
    } <"$command_path" 2>/dev/null || true
    if [[ $first_line != '# codyssey-init: managed-j-v1' ]] \
      && [[ $first_line != '#!/bin/sh' || $second_line != '# codyssey-init: managed-j-v1' ]]; then
      printf 'codyssey-init: preserving existing unowned command at %s\n' "$command_path" >&2
      return 0
    fi
  fi
  mkdir -p "$bin" || die 'could not create j command directory.'
  mise_path=$(command -v mise) || die 'mise is required to install the j wrapper.'
  [[ $mise_path == /* ]] || mise_path="$PWD/$mise_path"
  temporary=$(mktemp "$bin/.j.XXXXXX") || die 'could not create a temporary j wrapper.'
  if ! {
    printf '%s\n' '#!/bin/sh' '# codyssey-init: managed-j-v1' 'set -eu'
    printf 'cd -- '
    write_shell_quoted "$target"
    printf '\nexec '
    write_shell_quoted "$mise_path"
    printf ' exec -- just "$@"\n'
  } >"$temporary"; then
    rm -f "$temporary"
    die 'could not write the j wrapper.'
  fi
  if ! chmod 0700 "$temporary" || ! mv -f "$temporary" "$command_path"; then
    rm -f "$temporary"
    die 'could not install the j wrapper.'
  fi
}

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
install_managed_j "$root"
