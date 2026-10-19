#!/bin/sh

startup_preparation_dir=
startup_preparation_log=
startup_preparation_result=
startup_preparation_ready=
startup_preparation_pid=

clear_startup_preparation() {
  if [ -n "$startup_preparation_dir" ]; then
    rm -f "$startup_preparation_log" "$startup_preparation_result" \
      "$startup_preparation_result.tmp" "$startup_preparation_ready"
    rmdir "$startup_preparation_dir" 2>/dev/null || true
  fi
  startup_preparation_dir=
  startup_preparation_log=
  startup_preparation_result=
  startup_preparation_ready=
  startup_preparation_pid=
}

wait_for_preparation_exit() {
  local attempt=0
  while kill -0 "$startup_preparation_pid" 2>/dev/null && [ "$attempt" -lt 30 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
  done
  if kill -0 "$startup_preparation_pid" 2>/dev/null; then
    kill -KILL "$startup_preparation_pid" 2>/dev/null || true
  fi
  wait "$startup_preparation_pid" 2>/dev/null || true
}

cancel_startup_preparation() {
  if [ -n "$startup_preparation_pid" ] && kill -0 "$startup_preparation_pid" 2>/dev/null; then
    kill -TERM "$startup_preparation_pid" 2>/dev/null || true
    wait_for_preparation_exit
  fi
  clear_startup_preparation
}

wait_startup_preparation() {
  local preparation_result
  [ -n "$startup_preparation_pid" ] || return 1
  wait "$startup_preparation_pid" 2>/dev/null || true
  if [ -f "$startup_preparation_result" ]; then
    IFS= read -r preparation_result <"$startup_preparation_result"
  else
    preparation_result=1
  fi
  if [ "$preparation_result" -ne 0 ]; then
    printf 'codyssey-init: startup preparation failed (exit %s).\n' "$preparation_result" >&2
    [ ! -f "$startup_preparation_log" ] || cat "$startup_preparation_log" >&2
  fi
  clear_startup_preparation
  return "$preparation_result"
}

start_startup_preparation() {
  local root=$1
  [ -z "$startup_preparation_pid" ] || return 1
  startup_preparation_dir=$(mktemp -d "${TMPDIR:-/tmp}/codyssey-init-preparation.XXXXXX") || return 1
  chmod 0700 "$startup_preparation_dir" || {
    rmdir "$startup_preparation_dir"
    startup_preparation_dir=
    return 1
  }
  startup_preparation_log=$startup_preparation_dir/output.log
  startup_preparation_result=$startup_preparation_dir/result
  startup_preparation_ready=$startup_preparation_dir/ready
  : >"$startup_preparation_log"
  chmod 0600 "$startup_preparation_log"
  TS_AUTHKEY= bash "$root/scripts/prepare-startup.sh" \
    "$startup_preparation_result" "$startup_preparation_ready" \
    >"$startup_preparation_log" 2>&1 &
  startup_preparation_pid=$!
  while [ ! -f "$startup_preparation_ready" ] \
    && kill -0 "$startup_preparation_pid" 2>/dev/null; do
    sleep 0.05
  done
  [ -f "$startup_preparation_ready" ] || wait_startup_preparation
}

restore_startup_terminal() {
  if command -v restore_tty >/dev/null 2>&1; then
    restore_tty
  fi
}

finish_startup() {
  local startup_result=$?
  trap - EXIT
  restore_startup_terminal
  cancel_startup_preparation
  exit "$startup_result"
}

interrupt_startup() {
  local startup_result=$1
  trap - HUP INT TERM
  restore_startup_terminal
  cancel_startup_preparation
  exit "$startup_result"
}
