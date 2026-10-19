#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'codyssey-init: %s\n' "$*" >&2
  exit 1
}

remote_files=(
  .dockerignore .env.example Dockerfile README.md HANDOFF.md docker-compose.yml init.sh justfile
  macos-setup.sh mise.toml next-script.zsh tailnet.sh verify-macos-setup.py
  lib/auth.sh lib/preparation.sh lib/readiness.zsh lib/bootstrap-tools.sh gost/gost.yaml enable-korean.swift install.sh tailscale-entrypoint.sh
  chrome-extension/manifest.json chrome-extension/background.mjs chrome-extension/proxy.mjs
  chrome-extension/popup.html chrome-extension/popup.css chrome-extension/popup.mjs
  chrome-extension/README.md chrome-extension/startup.json scripts/install-chrome-extension.sh
  scripts/tailnet-browser.sh scripts/browser-version.sh scripts/install-gureum.sh
  scripts/configure-tailnet-browser.py
  scripts/install-tailnet-tools.sh scripts/tailnet-dns.sh
  scripts/prepare-startup.sh scripts/quiet-desktop.swift
)
remote_staging=

cleanup_remote_staging() {
  [[ -z $remote_staging ]] || rm -rf "$remote_staging"
}


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
  local target=$1 bin command_path first_line second_line temporary
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
  mkdir -p "$bin"
  temporary=$(mktemp "$bin/.j.XXXXXX") || die 'could not create a temporary j wrapper.'
  if ! {
    printf '%s\n' '#!/bin/sh' '# codyssey-init: managed-j-v1' 'set -eu'
    printf 'cd -- '
    write_shell_quoted "$target"
    printf '\nexec just "$@"\n'
  } >"$temporary"; then
    rm -f "$temporary"
    die 'could not write the j wrapper.'
  fi
  if ! chmod 0700 "$temporary" || ! mv -f "$temporary" "$command_path"; then
    rm -f "$temporary"
    die 'could not install the j wrapper.'
  fi
}

install_remote_files() {
  local target=$1 staging file destination
  staging=$(mktemp -d) || die 'could not create a staging directory.'
  remote_staging=$staging
  trap cleanup_remote_staging EXIT
  for file in "${remote_files[@]}"; do
    mkdir -p "$staging/$(dirname -- "$file")"
    curl --fail --location --silent --show-error \
      "https://raw.githubusercontent.com/mjy9088/codyssey-public/main/environment/codyssey-init/$file" -o "$staging/$file"
  done
  for file in init.sh tailnet.sh lib/auth.sh lib/preparation.sh lib/bootstrap-tools.sh macos-setup.sh \
    scripts/prepare-startup.sh; do
    bash -n "$staging/$file"
  done
  for file in next-script.zsh lib/readiness.zsh; do
    zsh -n "$staging/$file"
  done
  for file in "${remote_files[@]}"; do
    destination="$target/$file"
    if [[ $file == gost/gost.yaml && -e $destination ]]; then
      continue
    fi
    if [[ -e $destination ]] && ! cmp -s "$staging/$file" "$destination"; then
      die "refusing to overwrite modified $destination"
    fi
  done
  mkdir -p "$target/gost" "$target/lib"
  for file in "${remote_files[@]}"; do
    destination="$target/$file"
    if [[ $file == gost/gost.yaml && -e $destination ]] || [[ -e $destination ]]; then
      continue
    fi
    mkdir -p "$(dirname -- "$destination")"
    install -m 0644 "$staging/$file" "$destination"
  done
  chmod 0755 "$target/init.sh" "$target/next-script.zsh" "$target/tailnet.sh" \
    "$target/macos-setup.sh" "$target/verify-macos-setup.py" "$target/lib/auth.sh"
  rm -rf "$staging"
  remote_staging=
  trap - EXIT
}

source_path=${BASH_SOURCE[0]:-}
if [[ -n $source_path && -f $source_path ]]; then
  source_dir=$(CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P)
else
  source_dir=
fi

if [[ -n $source_dir && -f $source_dir/next-script.zsh ]]; then
  init_dir=${CODYSSEY_INIT_DIR:-$source_dir}
  [[ $init_dir == "$source_dir" ]] || die 'a local checkout must run in place; unset CODYSSEY_INIT_DIR.'
else
  init_dir=${CODYSSEY_INIT_DIR:-"$HOME/.local/share/codyssey-init"}
  command -v curl >/dev/null 2>&1 || die 'remote mode requires curl.'
  install_remote_files "$init_dir"
fi
init_dir=$(CDPATH= cd -- "$init_dir" && pwd -P)

. "$init_dir/lib/bootstrap-tools.sh"
prepare_docker
command -v zsh >/dev/null 2>&1 || die 'zsh is required.'
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
command -v mise >/dev/null 2>&1 || install_mise
. "$init_dir/lib/preparation.sh"
. "$init_dir/lib/auth.sh"
trap finish_startup EXIT
trap 'interrupt_startup 129' HUP
trap 'interrupt_startup 130' INT
trap 'interrupt_startup 143' TERM
printf 'Preparing environment…\n'
start_startup_preparation "$init_dir"

if [[ -t 1 ]] && { true </dev/tty && true >/dev/tty; } 2>/dev/null; then
  printf 'Install the global j command in %s? [y/N] ' "$HOME/.local/bin" >/dev/tty
  IFS= read -r install_j_answer </dev/tty || install_j_answer=
  case $install_j_answer in
    y|Y|yes|YES) install_managed_j "$init_dir" ;;
    *) ;;
  esac
fi

zsh_dir=${ZDOTDIR:-$HOME}
zshrc="$zsh_dir/.zshrc"
mkdir -p "$zsh_dir"
touch "$zshrc"
if ! grep -q '^# codyssey-init: OrbStack tools$' "$zshrc"; then
  cat >>"$zshrc" <<'EOF'

# codyssey-init: OrbStack tools
for codyssey_orb_app in /Applications/OrbStack.app "$HOME/Applications/OrbStack.app"; do
  if [ -x "$codyssey_orb_app/Contents/MacOS/xbin/docker" ]; then
    export PATH="$PATH:$codyssey_orb_app/Contents/MacOS/xbin"
    break
  fi
done
unset codyssey_orb_app
EOF
fi
if ! grep -q '^# codyssey-init: mise$' "$zshrc"; then
  cat >>"$zshrc" <<'EOF'

# codyssey-init: mise
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
eval "$(mise activate zsh)"
EOF
fi

macos_setup=${CODYSSEY_MACOS_SETUP:-}
if [[ -z $macos_setup ]]; then
  if [[ $(uname -s) == Darwin ]]; then macos_setup=1; else macos_setup=0; fi
fi
[[ $macos_setup == 0 || $macos_setup == 1 ]] || die 'CODYSSEY_MACOS_SETUP must be 0 or 1.'
if [[ $macos_setup == 1 ]]; then
  if bash "$init_dir/macos-setup.sh"; then
    :
  else
    preference_status=$?
    printf 'codyssey-init: macOS preferences failed (exit %s); continuing container and browser setup.\n' "$preference_status" >&2
    printf 'Retry preferences separately: bash "%s/macos-setup.sh"\n' "$init_dir" >&2
  fi
fi

cd "$init_dir"
configure_tailscale_auth
wait_startup_preparation
if [[ -t 0 ]]; then
  exec zsh -i "$init_dir/next-script.zsh" --prepared
fi
if { true </dev/tty; } 2>/dev/null; then
  exec zsh -i "$init_dir/next-script.zsh" --prepared </dev/tty
fi
exec zsh -i "$init_dir/next-script.zsh" --prepared </dev/null
