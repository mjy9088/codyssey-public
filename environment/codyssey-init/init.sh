#!/usr/bin/env bash
set -euo pipefail

MISE_VERSION=v2026.10.5
MISE_MACOS_ARM64_SHA256=41c4028257d30f5f5742c99247c461f417143d6c7301f167a0c185247c8f206e
MISE_MACOS_X64_SHA256=204c7d64e8b0b62c0a95847ab6442bf23bf88247d52967e99c5cad53f56eaa0c

die() {
  printf 'codyssey-init: %s\n' "$*" >&2
  exit 1
}

prepare_docker() {
  local app tools plugin_dir plugin attempt
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return
  fi
  if [[ $(uname -s) == Darwin && -z ${DOCKER_HOST:-} && -z ${DOCKER_CONTEXT:-} ]]; then
    for app in /Applications/OrbStack.app "$HOME/Applications/OrbStack.app"; do
      tools="$app/Contents/MacOS/xbin"
      [[ -x $app/Contents/MacOS/bin/orb && -x $tools/docker ]] || continue
      # Keep an existing Docker CLI ahead of the bundled fallback.
      export PATH="$PATH:$tools"
      plugin_dir="${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins"
      mkdir -p "$plugin_dir"
      for plugin in docker-compose docker-buildx; do
        if [[ ! -e $plugin_dir/$plugin && ! -L $plugin_dir/$plugin && -x $tools/$plugin ]]; then
          ln -s "$tools/$plugin" "$plugin_dir/$plugin"
        fi
      done
      printf 'Starting OrbStack through its bundled CLI.\n'
      "$app/Contents/MacOS/bin/orb" start || die 'OrbStack could not start.'
      for ((attempt = 0; attempt < 60; attempt++)); do
        docker info >/dev/null 2>&1 && return
        sleep 1
      done
      die 'OrbStack started but Docker did not become ready within 60 seconds.'
    done
  fi
  command -v docker >/dev/null 2>&1 || die 'Docker is required; install OrbStack in /Applications first.'
  die 'Docker is installed but its selected engine is not running.'
}

remote_files=(
  .dockerignore .env.example Dockerfile README.md HANDOFF.md docker-compose.yml init.sh justfile
  macos-setup.sh mise.toml next-script.zsh tailnet.sh verify-macos-setup.py
  lib/auth.sh gost/gost.yaml enable-korean.swift install.sh tailscale-entrypoint.sh
  chrome-extension/manifest.json chrome-extension/background.mjs chrome-extension/proxy.mjs
  chrome-extension/popup.html chrome-extension/popup.css chrome-extension/popup.mjs
  chrome-extension/README.md chrome-extension/startup.json scripts/install-chrome-extension.sh
  scripts/tailnet-browser.sh scripts/browser-version.sh scripts/install-gureum.sh
  scripts/configure-tailnet-browser.py
  scripts/install-tailnet-tools.sh scripts/tailnet-dns.sh
)
remote_staging=
mise_download=

cleanup_remote_staging() {
  [[ -z $remote_staging ]] || rm -rf "$remote_staging"
}

cleanup_mise_download() {
  [[ -z $mise_download ]] || rm -f "$mise_download"
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
  local target=$1 base_url=$2 ref=$3 staging file destination
  [[ $base_url == https://* ]] || die 'CODYSSEY_INIT_BASE_URL must use HTTPS.'
  [[ $ref == main || $ref =~ ^[0-9a-f]{40}$ ]] || \
    die 'CODYSSEY_INIT_REF must be main or a full 40-character reviewed commit.'
  staging=$(mktemp -d) || die 'could not create a staging directory.'
  remote_staging=$staging
  trap cleanup_remote_staging EXIT
  for file in "${remote_files[@]}"; do
    mkdir -p "$staging/$(dirname -- "$file")"
    curl --fail --location --silent --show-error \
      "$base_url/$ref/environment/codyssey-init/$file" -o "$staging/$file"
  done
  bash -n "$staging/init.sh" "$staging/tailnet.sh" "$staging/lib/auth.sh" "$staging/macos-setup.sh"
  zsh -n "$staging/next-script.zsh"
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

install_mise() {
  local machine asset checksum download dependency
  [[ $(uname -s) == Darwin ]] || die 'automatic mise installation supports macOS only.'
  machine=$(uname -m)
  case $machine in
    arm64)
      asset="mise-$MISE_VERSION-macos-arm64"
      checksum=$MISE_MACOS_ARM64_SHA256
      ;;
    x86_64)
      asset="mise-$MISE_VERSION-macos-x64"
      checksum=$MISE_MACOS_X64_SHA256
      ;;
    *) die "automatic mise installation does not support macOS architecture $machine." ;;
  esac
  for dependency in curl shasum cut install mktemp; do
    command -v "$dependency" >/dev/null 2>&1 || die "installing mise requires $dependency."
  done
  download=$(mktemp) || die 'could not create a mise download file.'
  mise_download=$download
  trap cleanup_mise_download EXIT
  curl --fail --location --silent --show-error \
    "https://github.com/jdx/mise/releases/download/$MISE_VERSION/$asset" -o "$download"
  [[ $(shasum -a 256 "$download" | cut -d ' ' -f 1) == "$checksum" ]] \
    || die "mise $MISE_VERSION checksum verification failed."
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$download" "$HOME/.local/bin/mise"
  rm -f "$download"
  mise_download=
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
  base_url=${CODYSSEY_INIT_BASE_URL:-}
  ref=${CODYSSEY_INIT_REF:-}
  [[ -n $base_url ]] || die 'remote mode requires CODYSSEY_INIT_BASE_URL for a reviewed source.'
  command -v curl >/dev/null 2>&1 || die 'remote mode requires curl.'
  install_remote_files "$init_dir" "${base_url%/}" "$ref"
fi
init_dir=$(CDPATH= cd -- "$init_dir" && pwd -P)

prepare_docker
command -v zsh >/dev/null 2>&1 || die 'zsh is required.'
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
command -v mise >/dev/null 2>&1 || install_mise

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

if [[ ${CODYSSEY_MACOS_SETUP:-0} == 1 || $(uname -s) == Darwin ]]; then
  if bash "$init_dir/macos-setup.sh"; then
    :
  else
    preference_status=$?
    printf 'codyssey-init: macOS preferences failed (exit %s); continuing container and browser setup.\n' "$preference_status" >&2
    printf 'Retry preferences separately: bash "%s/macos-setup.sh"\n' "$init_dir" >&2
  fi
fi

if [[ -t 0 ]]; then
  exec zsh -i "$init_dir/next-script.zsh"
fi
if { true </dev/tty; } 2>/dev/null; then
  exec zsh -i "$init_dir/next-script.zsh" </dev/tty
fi
exec zsh -i "$init_dir/next-script.zsh" </dev/null
