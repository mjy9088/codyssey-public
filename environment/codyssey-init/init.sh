#!/usr/bin/env bash
set -euo pipefail

MISE_VERSION=v2026.10.5
MISE_MACOS_ARM64_SHA256=41c4028257d30f5f5742c99247c461f417143d6c7301f167a0c185247c8f206e
MISE_MACOS_X64_SHA256=204c7d64e8b0b62c0a95847ab6442bf23bf88247d52967e99c5cad53f56eaa0c

die() {
  printf 'codyssey-init: %s\n' "$*" >&2
  exit 1
}

remote_files=(
  .dockerignore .env.example Dockerfile README.md docker-compose.yml init.sh justfile
  macos-setup.sh mise.toml next-script.zsh tailnet.sh verify-macos-setup.py
  lib/auth.sh gost/gost.yaml
)
remote_staging=
mise_download=

cleanup_remote_staging() {
  [[ -z $remote_staging ]] || rm -rf "$remote_staging"
}

cleanup_mise_download() {
  [[ -z $mise_download ]] || rm -f "$mise_download"
}

install_remote_files() {
  local target=$1 base_url=$2 ref=$3 staging file destination
  [[ $base_url == https://* ]] || die 'CODYSSEY_INIT_BASE_URL must use HTTPS.'
  [[ $ref =~ ^[0-9a-f]{40}$ ]] || die 'CODYSSEY_INIT_REF must be a full 40-character reviewed commit.'
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

command -v docker >/dev/null 2>&1 || die 'Docker is required.'
docker info >/dev/null 2>&1 || die 'Docker is installed but its engine is not running.'
command -v zsh >/dev/null 2>&1 || die 'zsh is required.'
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
command -v mise >/dev/null 2>&1 || install_mise

zsh_dir=${ZDOTDIR:-$HOME}
zshrc="$zsh_dir/.zshrc"
mkdir -p "$zsh_dir"
touch "$zshrc"
if ! grep -q '^# codyssey-init: mise$' "$zshrc"; then
  cat >>"$zshrc" <<'EOF'

# codyssey-init: mise
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
eval "$(mise activate zsh)"
EOF
fi

if [[ ${CODYSSEY_MACOS_SETUP:-0} == 1 ]]; then
  bash "$init_dir/macos-setup.sh" || printf 'Optional macOS preferences failed; continuing.\n' >&2
fi

exec zsh -i "$init_dir/next-script.zsh" </dev/null
