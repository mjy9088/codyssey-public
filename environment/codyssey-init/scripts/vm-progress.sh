#!/usr/bin/env bash
# Keep native tool output and exit status, with a heartbeat for silent phases.
vm_progress() (
  label=$1
  shift
  started=$SECONDS
  printf '%s…\n' "$label" >&2
  (
    timer=
    trap 'if [[ -n $timer ]]; then kill "$timer" 2>/dev/null || :; fi; exit' TERM
    while :; do
      sleep 10 &
      timer=$!
      wait "$timer"
      timer=
      detail=
      if [[ -n ${vm_progress_path:-} ]] && size=$(du -sk "$vm_progress_path" 2>/dev/null); then
        detail="; $(( ${size%%[[:space:]]*} / 1024 )) MiB written"
      fi
      printf '\n%s… %ss elapsed%s\n' "$label" "$((SECONDS - started))" "$detail" >&2
    done
  ) &
  reporter=$!
  trap 'kill "$reporter" 2>/dev/null || :; wait "$reporter" 2>/dev/null || :' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
)
