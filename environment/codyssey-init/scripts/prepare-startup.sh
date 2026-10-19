#!/usr/bin/env bash
set -euo pipefail
set -m

[[ $# -eq 2 ]] || { printf 'prepare-startup: internal result and ready paths are required.\n' >&2; exit 2; }
result_path=$1
ready_path=$2
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$root"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
export TS_AUTHKEY=
preparation_groups=

record_preparation_result() {
  local preparation_result=$?
  trap - EXIT
  printf '%s\n' "$preparation_result" >"$result_path.tmp"
  mv "$result_path.tmp" "$result_path"
  exit "$preparation_result"
}

group_is_alive() {
  kill -0 -- "-$1" 2>/dev/null
}

terminate_preparation_groups() {
  local group attempt active
  for group in $preparation_groups; do
    kill -TERM -- "-$group" 2>/dev/null || true
  done
  attempt=0
  while [ "$attempt" -lt 20 ]; do
    active=0
    for group in $preparation_groups; do
      group_is_alive "$group" && active=1
    done
    [ "$active" -eq 1 ] || break
    sleep 0.1
    attempt=$((attempt + 1))
  done
  for group in $preparation_groups; do
    group_is_alive "$group" && kill -KILL -- "-$group" 2>/dev/null || true
  done
  for group in $preparation_groups; do
    wait "$group" 2>/dev/null || true
  done
  preparation_groups=
}

cancel_preparation() {
  local signal_status=$1
  trap - HUP INT TERM
  terminate_preparation_groups
  exit "$signal_status"
}

run_preparation_step() {
  local step_pid step_result
  "$@" &
  step_pid=$!
  preparation_groups=$step_pid
  if wait "$step_pid"; then step_result=0; else step_result=$?; fi
  preparation_groups=
  return "$step_result"
}

prepare_container_images() {
  local build_pid pull_pid build_result pull_result
  docker compose build tailscale &
  build_pid=$!
  docker compose pull gost gost-ui &
  pull_pid=$!
  preparation_groups="$build_pid $pull_pid"
  : >"$ready_path"
  if wait "$build_pid"; then build_result=0; else build_result=$?; fi
  preparation_groups=$pull_pid
  if [[ $build_result -ne 0 ]]; then
    terminate_preparation_groups
    return "$build_result"
  fi
  if wait "$pull_pid"; then pull_result=0; else pull_result=$?; fi
  preparation_groups=
  return "$pull_result"
}

trap 'cancel_preparation 129' HUP
trap 'cancel_preparation 130' INT
trap 'cancel_preparation 143' TERM
trap record_preparation_result EXIT

prepare_container_images
run_preparation_step mise trust "$root/mise.toml"
run_preparation_step mise install just@1.43.0
