#!/usr/bin/env bash
# Host-side disposable VM lifecycle for the GUI Gureum check.
set -euo pipefail

usage() {
  printf 'Usage: bash scripts/run-tart-input-check.sh BASE_VM [--expect-recovery]\n'
  printf 'Use a stopped local Tart base with a guest agent, Swift, and an auto-login desktop user.\n'
}
if [[ ${1:-} == --help ]]; then usage; exit 0; fi
[[ $# -ge 1 && $# -le 2 && $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ &&
   ( $# == 1 || $2 == --expect-recovery ) ]] || { usage >&2; exit 2; }
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || {
  printf 'Use an Apple Silicon macOS host.\n' >&2; exit 1;
}
for tool in mise uv; do
  command -v "$tool" >/dev/null || { printf 'Missing host tool: %s\n' "$tool" >&2; exit 1; }
done
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tart=$(mise -C "$root" -E vm which tart)
export TART_NO_AUTO_PRUNE=1
umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/codyssey-input.XXXXXX")
log="$work/tart.log"
name="codyssey-input-${work##*.}"
created=0 runner=
cleanup() {
  result=$?
  trap - EXIT
  if [[ -n $runner ]] && kill -0 "$runner" 2>/dev/null; then
    if ! "$tart" stop "$name"; then
      printf 'Could not stop %s. Private VNC log retained at %s\n' "$name" "$log" >&2
      exit 1
    fi
  fi
  if [[ -n $runner ]]; then wait "$runner" 2>/dev/null || true; fi
  if (( created )); then
    if (( result == 0 )); then
      "$tart" delete "$name" || result=1
    fi
    if (( result != 0 )); then printf 'VM retained for diagnosis: %s\n' "$name" >&2; fi
  fi
  rm -rf "$work"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$tart" clone "$1" "$name"
created=1
"$tart" run --no-graphics --vnc-experimental "$name" >"$log" 2>&1 &
runner=$!
printf 'VM: %s\nPrivate VNC log: %s\n' "$name" "$log"
ready=0
for attempt in {1..15}; do
  kill -0 "$runner" 2>/dev/null || { printf 'Tart stopped before the VM was ready.\n' >&2; exit 1; }
  if grep -q 'VNC server is running at ' "$log" &&
     "$tart" exec "$name" /usr/bin/true >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
(( ready )) || { printf 'VM did not expose VNC and a ready guest agent.\n' >&2; exit 1; }
shift
uv run --no-project --with vncdotool==1.4.2 python "$root/scripts/verify-tart-input.py" "$name" "$log" "$@"
