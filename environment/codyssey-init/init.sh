#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'codyssey-init: %s\n' "$*" >&2
  if command -v log_event >/dev/null 2>&1; then log_event run failed; fi
  exit 1
}

remote_files=(
  init.sh next-script.zsh .dockerignore .env.example Dockerfile README.md docker-compose.yml justfile
  macos-setup.sh mise.toml tailnet.sh verify-macos-setup.py
  lib/auth.sh lib/options.sh lib/logging.sh lib/preparation.sh lib/readiness.zsh lib/bootstrap-tools.sh gost/gost.yaml enable-korean.swift tailscale-entrypoint.sh
  chrome-extension/manifest.json chrome-extension/background.mjs chrome-extension/proxy.mjs
  chrome-extension/popup.html chrome-extension/popup.css chrome-extension/popup.mjs
  chrome-extension/README.md chrome-extension/startup.json scripts/install-chrome-extension.sh
  scripts/tailnet-browser.sh scripts/browser-version.sh scripts/install-gureum.sh
  scripts/configure-tailnet-browser.py
  scripts/install-tailnet-tools.sh scripts/tailnet-dns.sh
  sdk/setup.mts sdk/cli.mts scripts/install-managed-j.sh
  scripts/prepare-startup.sh scripts/install-iterm2.sh scripts/configure-iterm2.sh scripts/configure-shell.sh
  tunnel-ui/.dockerignore tunnel-ui/Dockerfile tunnel-ui/package.json tunnel-ui/package-lock.json tunnel-ui/index.html
  tunnel-ui/src/App.tsx tunnel-ui/src/styles.css
  tunnel-ui/server/main.mjs tunnel-ui/server/http.mjs tunnel-ui/server/tunnels.mjs
  tunnel-ui/server/gost.mjs tunnel-ui/server/config-file.mjs tunnel-ui/server/policy.mjs
)
remote_staging=
remote_publish_temps=()
remote_created_dirs=()

cleanup_remote_staging() {
  local temp
  for temp in ${remote_publish_temps[@]+"${remote_publish_temps[@]}"}; do
    rm -f "$temp"
  done
  for temp in ${remote_created_dirs[@]+"${remote_created_dirs[@]}"}; do
    rmdir "$temp" 2>/dev/null || true
  done
  [[ -z $remote_staging ]] || rm -rf "$remote_staging"
}

# SHA-256 of changed managed files from accepted a2838076abf01d03c02e672408adac51560a6c9b.
# These are the exact downloaded bytes; user state is deliberately not an upgrade candidate.
legacy_remote_digest() {
  case $1 in
    chrome-extension/README.md) printf '%s\n' 485cf8c9744eceaffb763e9073a172e27b8dcf844772abb7e7e6c47f057d538c ;;
    chrome-extension/popup.html) printf '%s\n' d6b62d955f29150b09a82c97e54b4e22df6cb3a4c3ba57447d2349b99afc0aef ;;
    docker-compose.yml) printf '%s\n' c0e711835fff709e12e3f477fe142e7166d40033283ccfcc050cecc4a070181c ;;
    init.sh) printf '%s\n' 0744d9eee4fad347b85e884ea410949e720cae6c204d2b72638b863c94ac70ef ;;
    justfile) printf '%s\n' da73643709c268bf88fa15ff7a6461db768e641f0a67918cf019962c6dec9979 ;;
    lib/readiness.zsh) printf '%s\n' f11477ea0da88b7339f5706c110b968ff53d7baf3629326625fac73963e1c203 ;;
    next-script.zsh) printf '%s\n' 47c9471ebbdb40c22bc93748386f8a6857f89bfc5cd5777197b65ca3682e4aee ;;
    scripts/prepare-startup.sh) printf '%s\n' 1e8e6770c01458c97758ab323da2e5bbbbb05659b0d0b941254533f647e67b87 ;;
    scripts/tailnet-browser.sh) printf '%s\n' 373d0dcf3c681aec0f3e5afc4addca9804b4cb8ab348e09e9e0e449b7ba380d0 ;;
    sdk/setup.mts) printf '%s\n' b89278ee63e51eba4eb5de9a0a251bd508f1b163d609bb530f978f687668e250 ;;
    *) return 1 ;;
  esac
}

refuse_remote_replacement() {
  die "refusing to overwrite modified $1. Back up and review this path, then restore the exact current or supported prior installer file, or move the conflicting path aside before retrying. Keep .env and gost/gost.yaml in place."
}

# Observe ownership for the entire manifest without changing target paths.
remote_file_state() {
  local target=$1 staging=$2 file=$3
  local destination="$target/$file" parent=$file expected digest
  if [[ $file == gost/gost.yaml && ( -e $destination || -L $destination ) ]]; then
    printf '%s\n' preserved
    return
  fi
  while [[ $parent == */* ]]; do
    parent=${parent%/*}
    if [[ -L $target/$parent || ( -e $target/$parent && ! -d $target/$parent ) ]]; then
      refuse_remote_replacement "$target/$parent"
    fi
  done
  if [[ ! -e $destination && ! -L $destination ]]; then
    printf '%s\n' missing
    return
  fi
  [[ -f $destination && ! -L $destination ]] || refuse_remote_replacement "$destination"
  if cmp -s "$staging/$file" "$destination"; then
    printf '%s\n' current
    return
  fi
  expected=$(legacy_remote_digest "$file") || refuse_remote_replacement "$destination"
  if command -v sha256sum >/dev/null 2>&1; then
    digest=$(sha256sum <"$destination") || die "could not hash $destination"
  elif command -v shasum >/dev/null 2>&1; then
    digest=$(shasum -a 256 <"$destination") || die "could not hash $destination"
  else
    die "install sha256sum or shasum to identify the prior installer file $destination"
  fi
  [[ ${digest%% *} == "$expected" ]] || refuse_remote_replacement "$destination"
  printf '%s\n' predecessor
}

lock_remote_install() {
  local lock="$1/.codyssey-installer.lock" mask
  [[ ! -L $lock && ( ! -e $lock || -f $lock ) ]] || refuse_remote_replacement "$lock"
  mask=$(umask)
  umask 077
  exec 9>>"$lock" || die "could not open installer lock $lock"
  umask "$mask"
  # Keep ownership on the open descriptor, not on a PID or removable path.
  if command -v flock >/dev/null 2>&1; then
    flock -n 9 || die "another installer is using $1, or its filesystem does not support locking. Retry after it exits."
  elif command -v perl >/dev/null 2>&1; then
    perl -MFcntl=:flock -e 'open my $lock, ">&=9" or exit 1; flock($lock, LOCK_EX | LOCK_NB) or exit 1' ||
      die "another installer is using $1, or its filesystem does not support locking. Retry after it exits."
  else
    die 'remote installation requires flock or system Perl for the installer lock.'
  fi
}

check_remote_tunnel_upgrade() (
  cd "$1"
  . "$2/lib/readiness.zsh"
  export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
  if ! command -v docker >/dev/null 2>&1 && [[ $(uname -s) == Darwin && -z ${DOCKER_HOST:-} && -z ${DOCKER_CONTEXT:-} ]]; then
    local app
    for app in "${CODYSSEY_APPLICATIONS_DIR:-/Applications}/OrbStack.app" "$HOME/Applications/OrbStack.app"; do
      [[ -x $app/Contents/MacOS/xbin/docker ]] || continue
      export PATH="$PATH:$app/Contents/MacOS/xbin"
      break
    done
  fi
  check_tunnel_upgrade
)

prepare_remote_directory() {
  local directory=$1
  [[ ! -L $directory ]] || refuse_remote_replacement "$directory"
  if [[ -d $directory ]]; then return; fi
  prepare_remote_directory "${directory%/*}"
  mkdir "$directory" || die "could not prepare $directory"
  remote_created_dirs=("$directory" ${remote_created_dirs[@]+"${remote_created_dirs[@]}"})
}

stage_remote_file() {
  local target=$1 staging=$2 file=$3 index=$4
  local destination="$target/$file" mode=0644 temp
  case $file in
    init.sh|next-script.zsh|tailnet.sh|macos-setup.sh|verify-macos-setup.py|lib/auth.sh) mode=0755 ;;
  esac
  prepare_remote_directory "${destination%/*}"
  temp=$(mktemp "${destination%/*}/.codyssey-init.XXXXXX") || die "could not stage $destination"
  remote_publish_temps[index]=$temp
  install -m "$mode" "$staging/$file" "$temp" || die "could not stage $destination"
}

require_remote_file_state() {
  local observed
  observed=$(remote_file_state "$1" "$2" "$3") || exit 1
  [[ $observed == "$4" ]] || refuse_remote_replacement "$1/$3"
}

publish_remote_file() {
  local temp=$1 destination=$2 expected=$3
  # Address the exact path even if it becomes a directory. Creating a name must
  # fail if another process has already created it, not replace its contents.
  if [[ $OSTYPE == darwin* ]]; then
    perl -e 'my ($state, $src, $dst) = @ARGV;
      ($state eq "missing" ? link($src, $dst) : rename($src, $dst)) or die "$dst: $!\n";' \
      "$expected" "$temp" "$destination"
  elif [[ $expected == missing ]]; then
    ln -T "$temp" "$destination"
  else
    mv -fT "$temp" "$destination"
  fi || die "could not publish $destination safely. Back up and review any changes before rerunning the remote installer."
}

apply_remote_release() {
  local target=$1 staging=$2 pending="$1/.codyssey-install-pending"
  local index file replacing=0 writing=0
  local -a states=()
  [[ ! -L $pending && ( ! -e $pending || -d $pending ) ]] || refuse_remote_replacement "$pending"
  for index in "${!remote_files[@]}"; do
    states[index]=$(remote_file_state "$target" "$staging" "${remote_files[index]}")
    if [[ ${states[index]} == predecessor ]]; then replacing=1; fi
  done
  if (( replacing )); then check_remote_tunnel_upgrade "$target" "$staging"; fi

  for index in "${!remote_files[@]}"; do
    case ${states[index]} in
      missing|predecessor)
        stage_remote_file "$target" "$staging" "${remote_files[index]}" "$index"
        writing=1
        ;;
    esac
  done

  # The engine query can block. Finish it before checking the complete set again.
  if (( replacing )); then check_remote_tunnel_upgrade "$target" "$staging"; fi
  for index in "${!remote_files[@]}"; do
    require_remote_file_state "$target" "$staging" "${remote_files[index]}" "${states[index]}"
  done

  # Persist the incomplete state until every rename succeeds. Enable the new
  # entry-point guards first so an interrupted upgrade cannot start a mixed release.
  if (( writing )) && [[ ! -d $pending ]]; then mkdir "$pending"; fi
  for index in "${!remote_files[@]}"; do
    [[ ${remote_publish_temps[index]+x} ]] || continue
    file=${remote_files[index]}
    require_remote_file_state "$target" "$staging" "$file" "${states[index]}"
    publish_remote_file "${remote_publish_temps[index]}" "$target/$file" "${states[index]}"
  done
  if [[ -d $pending ]]; then rmdir "$pending"; fi
}

install_remote_files() {
  local target=$1 staging file
  staging=$(mktemp -d) || die 'could not create a staging directory.'
  remote_staging=$staging
  trap cleanup_remote_staging EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  for file in "${remote_files[@]}"; do
    mkdir -p "$staging/$(dirname -- "$file")"
    curl --fail --location --silent --show-error \
      "https://raw.githubusercontent.com/mjy9088/codyssey-public/main/environment/codyssey-init/$file" -o "$staging/$file"
  done
  for file in init.sh tailnet.sh lib/auth.sh lib/options.sh lib/logging.sh lib/preparation.sh lib/bootstrap-tools.sh macos-setup.sh \
    scripts/prepare-startup.sh scripts/install-managed-j.sh; do
    bash -n "$staging/$file"
  done
  for file in next-script.zsh lib/readiness.zsh; do
    zsh -n "$staging/$file"
  done
  mkdir -p "$target"
  target=$(CDPATH= cd -- "$target" && pwd -P)
  lock_remote_install "$target"
  apply_remote_release "$target" "$staging"
  cleanup_remote_staging
  remote_staging=
  trap - EXIT
}

source_path=${BASH_SOURCE[0]:-}
if [[ -n $source_path && -f $source_path ]]; then
  source_dir=$(CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P)
else
  source_dir=
fi

remote_install=0
if [[ -n $source_dir && -f $source_dir/next-script.zsh ]]; then
  init_dir=${CODYSSEY_INIT_DIR:-$source_dir}
  [[ $init_dir == "$source_dir" ]] || die 'a local checkout must run in place; unset CODYSSEY_INIT_DIR.'
  if [[ -e $init_dir/.codyssey-installer.lock || -L $init_dir/.codyssey-installer.lock ]]; then
    lock_remote_install "$init_dir"
    remote_install=1
  fi
  [[ ! -e $init_dir/.codyssey-install-pending && ! -L $init_dir/.codyssey-install-pending ]] ||
    die 'an installer update is incomplete. Rerun the normal remote installer to finish before starting Codyssey.'
else
  init_dir=${CODYSSEY_INIT_DIR:-"$HOME/.local/share/codyssey-init"}
  command -v curl >/dev/null 2>&1 || die 'remote mode requires curl.'
  remote_install=1
  install_remote_files "$init_dir"
fi
init_dir=$(CDPATH= cd -- "$init_dir" && pwd -P)

. "$init_dir/lib/logging.sh"
init_run_log new
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
sdk_node=
run_sdk() {
  "$sdk_node" "$init_dir/sdk/cli.mts" "$@"
}

ensure_sdk_runtime() {
  [[ -n $sdk_node ]] && return 0
  if node_runs_setup_sdk "$init_dir"; then
    sdk_node=$(command -v node)
    return 0
  fi
  local managed_node
  if { [[ $tools_ready == 1 ]] || ensure_mise; } &&
     run_quiet_step 'Installing Node for the setup SDK' mise install "$MISE_SETUP_NODE" &&
     managed_node=$(mise_setup_node_path); then
    sdk_node=$managed_node
    return 0
  fi
  printf 'codyssey-init: setup requires Node.js 22.18 or newer.\n' >&2
  return 1
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
  if ensure_sdk_runtime; then :; else container_status=1; fi
  if [[ $container_status == 0 ]]; then
    printf 'Preparing optional Tailnet environment…\n'
    if start_startup_preparation "$init_dir" "$sdk_node" "$init_dir/sdk/cli.mts" prepare-worker; then :; else container_status=$?; fi
  fi
else
  log_event tailnet skipped
fi

j_setup=$(choose_setup_option "${CODYSSEY_INSTALL_J:-}" 'Install optional Tailnet j command and Dock launcher?')
if [[ $j_setup == 1 ]]; then
  if [[ $tools_ready == 1 ]] || ensure_mise; then
    if ensure_sdk_runtime && run_sdk install-launcher; then log_event j installed; else log_event j failed; fi
  else
    printf 'j command installation failed; continuing remaining setup.\n' >&2
  fi
else
  log_event j skipped
fi
if [[ $tools_ready == 1 ]] && ensure_sdk_runtime; then
  if run_quiet_step "Configuring shell" run_sdk configure-shell; then :; else
    printf 'Shell configuration failed; continuing remaining setup.\n' >&2
  fi
fi

macos_setup=0
workstation_incomplete=0
if [[ $(uname -s) == Darwin ]]; then
  macos_setup=$(choose_setup_option "${CODYSSEY_MACOS_SETUP:-}" 'Apply optional macOS keyboard, text and Dock preferences?')
fi
if [[ $(uname -s) == Darwin ]] && ensure_sdk_runtime; then
  if run_quiet_step "Installing iTerm2" run_sdk install-iterm2; then :; else
    workstation_incomplete=1
    printf 'iTerm2 installation failed; continuing remaining setup.\n' >&2
  fi
  if run_quiet_step "Configuring iTerm2 keyboard" run_sdk configure-iterm2; then :; else
    workstation_incomplete=1
    printf 'iTerm2 keyboard configuration failed; continuing remaining setup.\n' >&2
  fi
elif [[ $(uname -s) == Darwin ]]; then
  workstation_incomplete=1
fi
if [[ $(uname -s) == Darwin && ( $macos_setup == 1 || $j_setup == 1 ) ]] && [[ -n $sdk_node ]]; then
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
    workstation_incomplete=1
    log_event preferences "incomplete exit=$preference_status"
    printf 'codyssey-init: macOS preferences failed (exit %s); continuing remaining setup.\n' "$preference_status" >&2
    printf 'Retry preferences separately: bash "%s/macos-setup.sh"\n' "$init_dir" >&2
  fi
else
  log_event preferences skipped
fi
if [[ $workstation_incomplete == 1 && ( $tailnet_setup == 0 || $container_status != 0 ) ]]; then
  printf 'Workstation setup is incomplete. See the warnings above for details.\n' >&2
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
export CODYSSEY_WORKSTATION_INCOMPLETE=$workstation_incomplete
start_installed_services() {
  if (( ! remote_install )); then exec "$sdk_node" "$init_dir/sdk/cli.mts" start-prepared; fi
  local status=0
  CODYSSEY_INTERACTIVE_SHELL=0 run_sdk start-prepared || status=$?
  # The installed startup (including readiness) has finished. An interactive
  # shell is not part of the installer transaction.
  exec 9>&-
  if (( status )); then
    trap - EXIT # The continuation already owns runtime failure diagnostics.
    exit "$status"
  fi
  if [[ -t 0 && -t 1 && ${CODYSSEY_INTERACTIVE_SHELL:-1} != 0 ]]; then exec zsh -i; fi
}
if [[ -t 0 ]]; then
  start_installed_services
elif { true </dev/tty; } 2>/dev/null; then
  start_installed_services </dev/tty
else
  start_installed_services </dev/null
fi
