#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help ]]; then
  printf 'Usage: bash scripts/verify-macos-vm.sh --disposable\nRuns real keyless Docker bootstrap and destructive preferences verification in an existing macOS VM.\n'
  exit 0
fi
[[ $# == 1 && $1 == --disposable ]] || { printf 'Use --disposable: this changes the VM user shell and preferences.\n' >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || { printf 'This verifier requires macOS.\n' >&2; exit 1; }
export PATH="/opt/homebrew/opt/python@3.13/libexec/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH"
[[ $(id -u) != 0 ]] || { printf 'Run as the VM desktop user, not root.\n' >&2; exit 1; }
for tool in docker python3 curl zsh nc; do
  command -v "$tool" >/dev/null || { printf 'Missing guest tool: %s\n' "$tool" >&2; exit 1; }
done
python3 -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ required"'
[[ -d '/Applications/Google Chrome.app' || -d "$HOME/Applications/Google Chrome.app" ]] || {
  printf 'Install Google Chrome in the disposable guest first.\n' >&2; exit 1;
}
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
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/vm-files.sh"

# Fixed production container names/host ports must not collide with an existing setup.
for name in tailnet-forward-tailscale tailnet-forward-gost tailnet-forward-ui; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    printf 'Existing %s container: use a clean disposable guest.\n' "$name" >&2; exit 1
  fi
done
for port in 18080 18081; do
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    printf 'Port %s is occupied: use a clean disposable guest.\n' "$port" >&2; exit 1
  fi
done
started=0 cleaned=0 work=
cleanup() {
  result=$1 cleanup_result=0
  (( cleaned == 0 )) || return "$result"
  cleaned=1
  trap - EXIT
  if (( started )); then
    if ! (cd "$work" && docker compose down --volumes); then
      printf 'Cleanup failed; private working directory retained at %s\n' "$work" >&2
      cleanup_result=1
    fi
  fi
  if (( cleanup_result == 0 )) && ! rm -rf "$work"; then
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
work=$(mktemp -d "$HOME/codyssey-vm-test.XXXXXX")
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
project_suffix=$(basename "$work" | tr '[:upper:].' '[:lower:]-' | tr -cd 'a-z0-9_-')
export COMPOSE_PROJECT_NAME="codyssey-vm-verify-$project_suffix"
state_volume="${COMPOSE_PROJECT_NAME}_tailscale-state"
if docker volume inspect "$state_volume" >/dev/null 2>&1; then
  printf 'Refusing pre-existing verifier state volume: %s\n' "$state_volume" >&2
  exit 1
fi
docker compose version >/dev/null
tar -C "$root" -cf - "${vm_files[@]}" | tar -C "$work" -xf -
mkdir -p "$work/gost"
cp "$root/tests/fixtures/gost.yaml" "$work/gost/gost.yaml"
cd "$work"
# Never inherit a real key, .env, project, or alternate Compose file from the caller.
export TS_AUTHKEY='' CODYSSEY_MACOS_SETUP=0 CODYSSEY_OPEN_BROWSER=0
unset CODYSSEY_INIT_DIR CODYSSEY_TTY_PATH ZDOTDIR
unset UNAME_BIN DEFAULTS_BIN PLISTBUDDY_BIN PLUTIL_BIN KILLALL_BIN
unset CODYSSEY_APPLICATIONS_DIR CODYSSEY_SYSTEM_APPLICATIONS_DIR
sh scripts/check.sh --native-python
started=1
for pass in 1 2; do
  printf 'Real macOS bootstrap, pass %s (no authentication)\n' "$pass"
  bash init.sh
  [[ ! -e .env ]] || { printf 'Exported empty key unexpectedly created .env.\n' >&2; exit 1; }
  state=$(docker compose exec -T tailscale tailscale status --json)
  printf '%s' "$state" | python3 -c 'import json,sys; assert json.load(sys.stdin)["BackendState"] == "NeedsLogin", "Expected unauthenticated NeedsLogin"'
  bash tailnet.sh bash -lc 'test -c /dev/net/tun; test -d /host; command -v bash; command -v ssh; command -v curl; command -v git'
  for endpoint in http://localhost:18080/config http://localhost:18081/; do
    endpoint_ready=0
    for (( attempt=0; attempt<60; attempt++ )); do
      if curl --fail --silent --max-time 2 "$endpoint" >/dev/null; then
        endpoint_ready=1
        break
      fi
      sleep 1
    done
    (( endpoint_ready )) || { printf 'Guest HTTP endpoint is not reachable: %s\n' "$endpoint" >&2; exit 1; }
  done
done
[[ $(grep -c '^# codyssey-init: mise$' "$HOME/.zshrc") == 1 ]]
CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 python3 verify-macos-setup.py
if cleanup 0; then
  :
else
  exit $?
fi
printf 'PASS: real macOS preferences and Docker bootstrap; Tailscale remains unauthenticated.\n'
