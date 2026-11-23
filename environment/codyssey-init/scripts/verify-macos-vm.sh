#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help ]]; then
  printf 'Usage: bash scripts/verify-macos-vm.sh --disposable [--workstation | --input-desktop]\n--workstation runs the live macOS setup and preferences checks without Docker.\n--input-desktop runs the interactive Gureum and Control-Space check.\nThe default also runs the keyless Docker bootstrap.\n'
  exit 0
fi
[[ ${1:-} == --disposable && ( $# == 1 ||
  ( $# == 2 && ( $2 == --workstation || $2 == --input-desktop || $2 == --input-from-console ) ) ) ]] || { printf 'Use --disposable: this changes the VM user shell and preferences.\n' >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || { printf 'This verifier requires macOS.\n' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { printf 'Run as the VM desktop user, not root.\n' >&2; exit 1; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/vm-guest-path.sh"
if [[ ${2:-} == --workstation ]]; then
  cd "$root"
  unset CODYSSEY_INIT_DIR CODYSSEY_TTY_PATH ZDOTDIR
  unset UNAME_BIN DEFAULTS_BIN PLISTBUDDY_BIN PLUTIL_BIN KILLALL_BIN
  unset CODYSSEY_APPLICATIONS_DIR CODYSSEY_SYSTEM_APPLICATIONS_DIR CODYSSEY_INPUT_SWITCH
  export TS_AUTHKEY='' CODYSSEY_TAILNET_SETUP=0 CODYSSEY_INSTALL_J=1 CODYSSEY_MACOS_SETUP=1
  export CODYSSEY_DOCK_SETUP=1 CODYSSEY_OPEN_BROWSER=0 CODYSSEY_INTERACTIVE_SHELL=0
  vm_guest_python_ready || { printf 'Python 3.10+ required.\n' >&2; exit 1; }
  . "$root/scripts/vm-progress.sh"
  if [[ ${CODYSSEY_FUSION_TEST_TYPING:-0} == 1 ]]; then
    vm_progress "Checking the preinstalled workstation apps" python3 scripts/check-preinstalled-apps.py --workstation
  fi
  vm_progress "Running workstation initialization" bash init.sh
  mise trust "$root/mise.toml"
  mise install
  CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 vm_progress "Checking the live macOS preferences" python3 verify-macos-setup.py
  /bin/zsh "$HOME/Library/Application Support/codyssey-init/Codyssey j.command" --list
  /usr/bin/swift enable-korean.swift --verify-shortcuts
  [[ $(/usr/bin/swift enable-korean.swift --current-source) == org.youknowone.inputmethod.Gureum.han2 ]]
  if [[ ${CODYSSEY_FUSION_TEST_TYPING:-0} == 1 ]]; then
    (
      work=$(mktemp -d "$root/.input-desktop.XXXXXX")
      transcript_pid=
      trap '
        if [[ -n $transcript_pid ]]; then
          kill "$transcript_pid" 2>/dev/null || :
          wait "$transcript_pid" 2>/dev/null || :
        fi
        rm -rf -- "$work"
      ' EXIT
      mkfifo "$work/transcript"
      /bin/cat "$work/transcript" &
      transcript_pid=$!
      cat > "$work/Verify Input.command" <<'COMMAND'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
umask 077
clear
/usr/bin/script -qF transcript /bin/bash ../scripts/verify-macos-vm.sh --disposable --input-from-console
result=$?
printf '%s\n' "$result" > status.tmp && mv status.tmp status
COMMAND
      chmod 700 "$work/Verify Input.command"
      printf 'Checking actual Hangul and Latin typing through the Fusion console.\n'
      /usr/bin/open -a Terminal "$work/Verify Input.command"
      deadline=$((SECONDS + 420))
      while [[ ! -f $work/status && $SECONDS -lt $deadline ]]; do sleep 2; done
      [[ -f $work/status ]] || { printf 'Timed out waiting for the Terminal typing check.\n' >&2; exit 1; }
      wait "$transcript_pid"
      transcript_pid=
      [[ $(cat "$work/status") == 0 ]]
    )
  else
    printf 'To verify typing in the guest Terminal, run: bash %q --disposable --input-desktop\n' "$0"
  fi
  printf 'PASS: macOS workstation setup, repeated preferences, Dock launcher and live shortcuts.\n'
  exit 0
fi
if [[ ${2:-} == --input-desktop || ${2:-} == --input-from-console ]]; then
  [[ -t 0 && -t 1 ]] || { printf 'Use Terminal in the disposable VM desktop.\n' >&2; exit 1; }
  unset DEFAULTS_BIN PLISTBUDDY_BIN PLUTIL_BIN UNAME_BIN CODYSSEY_INPUT_SWITCH
  helper="$root/enable-korean.swift"
  hangul=org.youknowone.inputmethod.Gureum.han2
  input_mode=$2
  vm_guest_desktop_prompt() {
    if [[ $input_mode == --input-from-console ]]; then
      local foreground
      foreground=$(/usr/bin/osascript -l JavaScript -e '
        ObjC.import("AppKit");
        ObjC.unwrap($.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier);
      ')
      [[ $foreground == com.apple.Terminal ]] || {
        printf 'Terminal lost focus during the typing check.\n' >&2
        exit 1
      }
      printf '\nCodyssey typing %s\n' "$1"
    fi
  }
  if [[ $2 == --input-desktop ]]; then
    . "$root/lib/bootstrap-tools.sh"
    node_bin=${CODYSSEY_VERIFY_NODE:-node}
    if [[ -z ${CODYSSEY_VERIFY_NODE:-} ]] && ! node_runs_setup_sdk "$root"; then
      node_bin=$(mise_setup_node_path) || {
        printf 'Run the workstation verification first to install the Node.js runtime through mise.\n' >&2
        exit 1
      }
    fi
    "$node_bin" "$root/sdk/cli.mts" configure-input
  fi
  [[ $(/usr/bin/swift "$helper" --current-source) == "$hangul" ]]
  # The first activation may leave a separate Input Monitoring dialog to dismiss.
  # Space commits the Hangul composition and can also insert a trailing space.
  vm_guest_desktop_prompt A
  printf 'With Gureum selected, type gks, then press Space and Return (expected 한): '
  IFS= read -r -t 120 typed || { printf 'Timed out waiting for desktop input.\n' >&2; exit 1; }
  [[ $typed == 한 || $typed == '한 ' ]] || { printf 'Hangul composition failed.\n' >&2; exit 1; }

  vm_guest_desktop_prompt B
  printf 'Press Control-Space to switch to Latin input.\n'
  /usr/bin/swift "$helper" --wait-for-source is-not "$hangul"
  vm_guest_desktop_prompt C
  printf 'Type abc and press Return: '
  IFS= read -r -t 60 typed || { printf 'Timed out waiting for desktop input.\n' >&2; exit 1; }
  latin=$(/usr/bin/swift "$helper" --current-source)
  [[ $typed == abc && -n $latin && $latin != "$hangul" ]] || {
    printf 'Control-Space did not switch to Latin input.\n' >&2; exit 1;
  }

  vm_guest_desktop_prompt D
  printf 'Press Control-Space again to switch to Hangul.\n'
  /usr/bin/swift "$helper" --wait-for-source is "$hangul"
  vm_guest_desktop_prompt E
  printf 'Type gks, then press Space and Return: '
  IFS= read -r -t 60 typed || { printf 'Timed out waiting for desktop input.\n' >&2; exit 1; }
  [[ ( $typed == 한 || $typed == '한 ' ) && $(/usr/bin/swift "$helper" --current-source) == "$hangul" ]] || {
    printf 'Control-Space did not switch back to Gureum Hangul.\n' >&2; exit 1;
  }
  printf 'PASS: Gureum activation, Hangul composition and Control-Space switching in both directions.\n'
  exit 0
fi
. "$root/lib/preparation.sh"
started=0 cleaned=0 work=
cleanup() {
  result=$1 cleanup_result=0
  (( cleaned == 0 )) || return "$result"
  cleaned=1
  trap - EXIT
  if (( started )); then
    if ! (cd "$work" && run_quiet_step 'Removing test services' docker compose down --volumes); then
      printf 'Cleanup failed; private working directory retained at %s\n' "$work" >&2
      cleanup_result=1
    fi
  fi
  if (( cleanup_result == 0 )) && [[ -n $work ]] && ! rm -rf "$work"; then
    printf 'Cleanup failed; private working directory retained at %s\n' "$work" >&2
    cleanup_result=1
  fi
  (( result != 0 )) && return "$result"
  return "$cleanup_result"
}
finish() {
  result=$?
  if cleanup "$result"; then
    exit 0
  else
    exit $?
  fi
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for tool in docker python3 curl zsh nc; do
  command -v "$tool" >/dev/null || { printf 'Missing guest tool: %s\n' "$tool" >&2; exit 1; }
done
vm_guest_python_ready || { printf 'Python 3.10+ required.\n' >&2; exit 1; }
[[ -z ${DOCKER_HOST:-} ]] || { printf 'DOCKER_HOST overrides are not allowed for VM verification.\n' >&2; exit 1; }
docker_context=${DOCKER_CONTEXT:-}
[[ -n $docker_context ]] || docker_context=$(docker context show)
docker_endpoint=$(docker context inspect "$docker_context" --format '{{ (index .Endpoints "docker").Host }}')
case $docker_endpoint in
  unix:///*) ;;
  *) printf 'Docker context %s is not a local absolute Unix socket.\n' "$docker_context" >&2; exit 1 ;;
esac
export DOCKER_CONTEXT=$docker_context
unset DOCKER_HOST DOCKER_TLS_VERIFY DOCKER_CERT_PATH
unset COMPOSE_FILE COMPOSE_ENV_FILES COMPOSE_PROFILES COMPOSE_PROJECT_NAME
docker info >/dev/null
. "$root/scripts/vm-files.sh"

# Fixed production container names/host ports must not collide with an existing setup.
for name in tailnet-forward-tailscale tailnet-forward-gost tailnet-forward-tunnel-ui tailnet-forward-ui; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    printf 'Existing %s container: use a clean disposable guest.\n' "$name" >&2; exit 1
  fi
done
for port in 18080 18081; do
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    printf 'Port %s is occupied: use a clean disposable guest.\n' "$port" >&2; exit 1
  fi
done
work=$(mktemp -d "$HOME/codyssey-vm-test.XXXXXX")
project_suffix=$(basename "$work" | tr '[:upper:].' '[:lower:]-' | tr -cd 'a-z0-9_-')
export COMPOSE_PROJECT_NAME="codyssey-vm-verify-$project_suffix"
docker compose version >/dev/null
tar -C "$root" -cf - "${vm_files[@]}" | tar -C "$work" -xf -
mkdir -p "$work/gost"
cp "$root/tests/fixtures/gost.yaml" "$work/gost/gost.yaml"
cd "$work"
# Never inherit a real key, .env, project, or alternate Compose file from the caller.
export TS_AUTHKEY='' CODYSSEY_TAILNET_SETUP=1 CODYSSEY_INSTALL_J=0 CODYSSEY_MACOS_SETUP=0 CODYSSEY_OPEN_BROWSER=0
export CODYSSEY_DOCK_SETUP=0 CODYSSEY_INTERACTIVE_SHELL=0
unset CODYSSEY_INIT_DIR CODYSSEY_TTY_PATH ZDOTDIR
unset UNAME_BIN DEFAULTS_BIN PLISTBUDDY_BIN PLUTIL_BIN KILLALL_BIN
unset CODYSSEY_APPLICATIONS_DIR CODYSSEY_SYSTEM_APPLICATIONS_DIR
unset CODYSSEY_INPUT_SWITCH
sh scripts/check.sh --native-python
started=1
for pass in 1 2; do
  printf 'Real macOS bootstrap, pass %s (no authentication)\n' "$pass"
  bash init.sh
  [[ ! -e .env ]] || { printf 'Exported empty key unexpectedly created .env.\n' >&2; exit 1; }
  state=$(docker compose exec -T tailscale tailscale status --json)
  printf '%s' "$state" | python3 -c 'import json,sys; assert json.load(sys.stdin)["BackendState"] == "NeedsLogin", "Expected unauthenticated NeedsLogin"'
  bash tailnet.sh bash -c 'test -c /dev/net/tun; test -d /host; command -v bash; command -v ssh; command -v curl; command -v git; mise --version; zellij --version'
  endpoint_ready=0
  for (( attempt=0; attempt<60; attempt++ )); do
    if curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18081/health >/dev/null; then
      endpoint_ready=1
      break
    fi
    sleep 1
  done
  (( endpoint_ready )) || { printf 'Codyssey tunnel manager is not ready in the guest.\n' >&2; exit 1; }
  if curl --noproxy '*' --silent --max-time 2 http://127.0.0.1:18080/config >/dev/null 2>&1; then
    printf 'Legacy GOST TCP control endpoint is still reachable.\n' >&2; exit 1
  fi
done
[[ $(grep -c '^# codyssey-init: mise$' "$HOME/.zshrc") == 1 ]]
# Exercise ephemeral lifecycle and local DNS using a private control plane, never a real tailnet.
python3 scripts/verify-tailnet-runtime.py --disposable
python3 scripts/verify-portable-browser.py --disposable
# Use the retained source tree, so Dock never points into the removed test copy.
CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 python3 "$root/verify-macos-setup.py" --desktop-only
swift "$root/enable-korean.swift" --shortcuts
swift "$root/enable-korean.swift" --verify-shortcuts
printf 'Gureum activation and typing pending. In the VM Terminal, run: bash %q --disposable --input-desktop\n' "$0"
if cleanup 0; then
  :
else
  exit $?
fi
printf 'PASS: real Dock launcher, live shortcuts and Docker bootstrap; Tailscale remains unauthenticated.\n'
