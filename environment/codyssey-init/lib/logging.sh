#!/bin/sh
# Persist only allowlisted lifecycle metadata. Never copy command output, auth
# input, environment variables, login URLs, or container logs into a shareable log.
init_run_log() {
  local directory
  directory="$HOME/Library/Logs/codyssey-init"
  if [ "${1:-}" != new ]; then
    case ${CODYSSEY_RUN_LOG:-} in
      "$directory"/run.[[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]])
        if [ -f "$CODYSSEY_RUN_LOG" ] && [ ! -L "$CODYSSEY_RUN_LOG" ]; then return 0; fi ;;
    esac
  fi
  CODYSSEY_RUN_LOG=
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

offer_diagnostic_upload() (
  local answer http_status
  local endpoint='https://logs.mj-y.com/logs/codyssey-public-init'
  [ -t 1 ] && [ -n "${CODYSSEY_RUN_LOG:-}" ] &&
    [ -f "$CODYSSEY_RUN_LOG" ] && [ ! -L "$CODYSSEY_RUN_LOG" ] || return 0
  { true </dev/tty; } 2>/dev/null || return 0
  exec 3<"$CODYSSEY_RUN_LOG" || return 0

  printf 'Send diagnostic log %s to %s? [Y/n] ' "$CODYSSEY_RUN_LOG" "$endpoint" || return 0
  IFS= read -r answer </dev/tty || return 0
  case $answer in
    ''|[Yy]|[Yy][Ee][Ss]) ;;
    *) return 0 ;;
  esac

  if http_status=$(curl --disable --silent --max-time 15 --output /dev/null \
    --write-out '%{http_code}' -H 'Content-Type: application/octet-stream' \
    --data-binary @- "$endpoint" <&3 3<&-); then
    case $http_status in
      2[0-9][0-9]) printf 'Diagnostic log sent.\n' >&2; return 0 ;;
    esac
  fi
  printf 'Could not send diagnostic log. Local copy: %s\n' "$CODYSSEY_RUN_LOG" >&2
)

log_event() {
  [ -n "${CODYSSEY_RUN_LOG:-}" ] || return 0
  # Callers supply fixed labels and exit statuses, never arbitrary tool output.
  printf '%s %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" >>"$CODYSSEY_RUN_LOG" 2>/dev/null || {
    printf 'codyssey-init: could not append diagnostic log.\n' >&2
    return 0
  }
}
