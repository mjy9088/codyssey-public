#!/usr/bin/env bash
# Shared by the installer and disposable-VM cold-start verification.
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/preparation.sh"
mise_download=
cleanup_mise_download() {
  [[ -z $mise_download ]] || rm -f "$mise_download"
}


MISE_VERSION=v2026.10.5
MISE_MACOS_ARM64_SHA256=41c4028257d30f5f5742c99247c461f417143d6c7301f167a0c185247c8f206e
MISE_MACOS_X64_SHA256=204c7d64e8b0b62c0a95847ab6442bf23bf88247d52967e99c5cad53f56eaa0c


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
      run_quiet_step "Starting OrbStack" "$app/Contents/MacOS/bin/orb" start || die 'OrbStack could not start.'
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

