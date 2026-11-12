#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'codyssey-init: %s\n' "$*" >&2
  if command -v log_event >/dev/null 2>&1; then log_event run failed; fi
  exit 1
}

remote_files=(
  .dockerignore .env.example Dockerfile README.md HANDOFF.md docker-compose.yml init.sh justfile
  macos-setup.sh mise.toml next-script.zsh tailnet.sh verify-macos-setup.py
  lib/auth.sh lib/options.sh lib/logging.sh lib/preparation.sh lib/readiness.zsh lib/bootstrap-tools.sh gost/gost.yaml enable-korean.swift tailscale-entrypoint.sh
  chrome-extension/manifest.json chrome-extension/background.mjs chrome-extension/proxy.mjs
  chrome-extension/popup.html chrome-extension/popup.css chrome-extension/popup.mjs
  chrome-extension/README.md chrome-extension/startup.json scripts/install-chrome-extension.sh
  scripts/tailnet-browser.sh scripts/browser-version.sh scripts/install-gureum.sh
  scripts/configure-tailnet-browser.py
  scripts/install-tailnet-tools.sh scripts/tailnet-dns.sh
  scripts/prepare-startup.sh scripts/install-ghostty.sh scripts/configure-shell.sh
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
  for file in init.sh tailnet.sh lib/auth.sh lib/options.sh lib/logging.sh lib/preparation.sh lib/bootstrap-tools.sh macos-setup.sh \
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

. "$init_dir/lib/logging.sh"
init_run_log
. "$init_dir/lib/options.sh"
. "$init_dir/lib/bootstrap-tools.sh"
. "$init_dir/lib/auth.sh"
trap finish_startup EXIT
trap 'interrupt_startup 129' HUP
trap 'interrupt_startup 130' INT
trap 'interrupt_startup 143' TERM
setup_has_terminal=0
if [[ -t 1 ]] && { true </dev/tty && true >/dev/tty; } 2>/dev/null; then setup_has_terminal=1; fi
tailnet_setup=$(choose_setup_option "${CODYSSEY_TAILNET_SETUP:-}" 'Configure optional Tailscale and GOST services?')
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
container_status=0
tools_ready=0
ensure_mise() {
  if command -v mise >/dev/null 2>&1 || (install_mise); then
    tools_ready=1
    log_event tools ready
  else
    log_event tools failed
    return 1
  fi
}
if [[ $tailnet_setup == 1 ]]; then
  if (prepare_docker); then
    for orb_app in "${CODYSSEY_APPLICATIONS_DIR:-/Applications}/OrbStack.app" "$HOME/Applications/OrbStack.app"; do
      [[ ! -x $orb_app/Contents/MacOS/xbin/docker ]] || export PATH="$PATH:$orb_app/Contents/MacOS/xbin"
    done
    log_event docker ready
  else
    container_status=1
    log_event docker failed
  fi
  if ensure_mise; then :; else container_status=1; fi
  if ! command -v zsh >/dev/null 2>&1; then container_status=1; log_event zsh missing; fi
  if [[ $container_status == 0 ]]; then
    printf 'Preparing optional Tailnet environment…\n'
    if start_startup_preparation "$init_dir"; then :; else container_status=$?; fi
  fi
else
  log_event tailnet skipped
fi

j_setup=$(choose_setup_option "${CODYSSEY_INSTALL_J:-}" 'Install optional Tailnet j command and Dock launcher?')
if [[ $j_setup == 1 ]]; then
  if [[ $tools_ready == 1 ]] || ensure_mise; then
    if (install_managed_j "$init_dir"); then log_event j installed; else log_event j failed; fi
  else
    printf 'j command installation failed; continuing remaining setup.\n' >&2
  fi
else
  log_event j skipped
fi
if [[ $tools_ready == 1 ]]; then
  if run_quiet_step "Configuring shell" bash "$init_dir/scripts/configure-shell.sh"; then :; else
    printf 'Shell configuration failed; continuing remaining setup.\n' >&2
  fi
fi

macos_setup=0
if [[ $(uname -s) == Darwin ]]; then
  macos_setup=$(choose_setup_option "${CODYSSEY_MACOS_SETUP:-}" 'Apply optional macOS keyboard, text and Dock preferences?')
fi
if [[ $(uname -s) == Darwin ]]; then
  if run_quiet_step "Installing Ghostty" bash "$init_dir/scripts/install-ghostty.sh"; then :; else
    printf 'Ghostty installation failed; continuing remaining setup.\n' >&2
  fi
fi
if [[ $(uname -s) == Darwin && ( $macos_setup == 1 || $j_setup == 1 ) ]]; then
  preference_mode=
  dock_cleanup=${CODYSSEY_DOCK_SETUP:-}
  if [[ $macos_setup == 0 ]]; then preference_mode=--desktop-only; dock_cleanup=${dock_cleanup:-0}; fi
  # Dock cleanup and launcher installation have separate ownership. Declining j
  # never creates a launcher; opting into j works without personal preferences.
  if CODYSSEY_DOCK_LAUNCHER=$j_setup CODYSSEY_DOCK_SETUP=$dock_cleanup \
    bash "$init_dir/macos-setup.sh" ${preference_mode:+"$preference_mode"}; then
    log_event preferences ready
  else
    preference_status=$?
    log_event preferences "incomplete exit=$preference_status"
    printf 'codyssey-init: macOS preferences failed (exit %s); continuing remaining setup.\n' "$preference_status" >&2
    printf 'Retry preferences separately: bash "%s/macos-setup.sh"\n' "$init_dir" >&2
  fi
else
  log_event preferences skipped
fi
if [[ $tailnet_setup == 0 ]]; then
  printf 'Setup finished. Optional Tailnet services were skipped; run the same init command again to choose options.\n'
  exit 0
fi
cd "$init_dir"
if [[ $container_status != 0 ]]; then
  printf "Container setup failed; independent workstation settings were still attempted. Run the same init command again to retry.\n" >&2
  exit "$container_status"
fi
configure_tailscale_auth
wait_startup_preparation
if [[ -t 0 ]]; then
  exec zsh -i "$init_dir/next-script.zsh" --prepared
fi
if { true </dev/tty; } 2>/dev/null; then
  exec zsh -i "$init_dir/next-script.zsh" --prepared </dev/tty
fi
exec zsh -i "$init_dir/next-script.zsh" --prepared </dev/null
