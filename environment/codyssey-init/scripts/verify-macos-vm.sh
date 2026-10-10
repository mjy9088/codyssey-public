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
docker info >/dev/null
docker compose version >/dev/null
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
work=$(mktemp -d "$HOME/codyssey-vm-test.XXXXXX")
started=0
cleanup() {
  result=$?
  trap - EXIT
  if (( started )); then
    if ! (cd "$work" && docker compose down --volumes); then
      printf 'Cleanup failed; private working directory retained at %s\n' "$work" >&2
      exit 1
    fi
  fi
  rm -rf "$work"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tar -C "$root" -cf - "${vm_files[@]}" | tar -C "$work" -xf -
mkdir -p "$work/gost"
cp "$root/tests/fixtures/gost.yaml" "$work/gost/gost.yaml"
cd "$work"
# Never inherit a real key, .env, project, or alternate Compose file from the caller.
export TS_AUTHKEY='' CODYSSEY_MACOS_SETUP=0 CODYSSEY_OPEN_BROWSER=0
export COMPOSE_PROJECT_NAME="codyssey-vm-verify-$$"
unset COMPOSE_FILE CODYSSEY_INIT_DIR CODYSSEY_TTY_PATH ZDOTDIR
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
  api_ready=0
  for (( attempt=0; attempt<30; attempt++ )); do
    if curl --fail --silent --max-time 2 http://localhost:18080/config >/dev/null; then
      api_ready=1
      break
    fi
    sleep 1
  done
  (( api_ready )) || { printf 'GOST API is not reachable from the macOS guest.\n' >&2; exit 1; }
  curl --fail --silent --show-error --max-time 10 http://localhost:18081/ >/dev/null
done
[[ $(grep -c '^# codyssey-init: mise$' "$HOME/.zshrc") == 1 ]]
CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 python3 verify-macos-setup.py
printf 'PASS: real macOS preferences and Docker bootstrap; Tailscale remains unauthenticated.\n'
