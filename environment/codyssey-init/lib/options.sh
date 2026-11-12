#!/usr/bin/env bash
# Explicit environment overrides also work in unattended runs. Empty/unset values
# prompt only through a controlling terminal; Enter and headless runs decline.
choose_setup_option() {
  local value=$1 label=$2 answer
  case $value in
    0|1) printf '%s\n' "$value"; return 0 ;;
    '') ;;
    *) printf 'codyssey-init: %s must be 0 or 1.\n' "$label" >&2; return 2 ;;
  esac
  if [[ ${setup_has_terminal:-0} == 1 ]]; then
    printf '%s [y/N] ' "$label" >/dev/tty
    IFS= read -r answer </dev/tty || answer=n
    case $answer in y|Y|yes|YES) printf '1\n'; return 0 ;; esac
  fi
  printf '0\n'
}
