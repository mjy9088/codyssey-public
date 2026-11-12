#!/bin/sh
# Persist only allowlisted lifecycle metadata. Never copy command output, auth
# input, environment variables, login URLs, or container logs into a shareable log.
init_run_log() {
  local directory
  [ -z "${CODYSSEY_RUN_LOG:-}" ] || return 0
  directory="$HOME/Library/Logs/codyssey-init"
  if ! (umask 077; mkdir -p "$directory" && chmod 0700 "$directory"); then
    printf 'codyssey-init: could not create diagnostic log directory.\n' >&2
    return 0
  fi
  CODYSSEY_RUN_LOG=$(umask 077; mktemp "$directory/run.XXXXXX") || return 0
  export CODYSSEY_RUN_LOG
  log_event run started
  log_event platform "$(uname -s) $(uname -m)"
  if command -v sw_vers >/dev/null 2>&1; then
    log_event macos "$(sw_vers -productVersion)"
  fi
  printf 'Diagnostic log (attach this file when reporting a problem): %s\n' "$CODYSSEY_RUN_LOG"
}

log_event() {
  [ -n "${CODYSSEY_RUN_LOG:-}" ] || return 0
  # Callers supply fixed labels and exit statuses, never arbitrary tool output.
  printf '%s %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" >>"$CODYSSEY_RUN_LOG" 2>/dev/null || {
    printf 'codyssey-init: could not append diagnostic log.\n' >&2
    return 0
  }
}
