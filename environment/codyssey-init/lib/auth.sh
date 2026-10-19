#!/usr/bin/env bash

extract_tailscale_auth_key() {
  local input=$1 key
  key=$(printf '%s\n' "$input" | grep -Eo "tskey-auth-[^[:space:]'\"]+" | head -n 1 || true)
  [[ $key =~ ^tskey-auth-[A-Za-z0-9_-]+$ ]] || return 1
  printf '%s\n' "$key"
}

restore_tty() {
  if [[ -n ${tty_state:-} ]]; then
    stty "$tty_state" <"$tty_path" 2>/dev/null || true
    tty_state=
  fi
}

configure_tailscale_auth() {
  local auth_input auth_key
  if [[ -n ${TS_AUTHKEY+x} || -e .env ]]; then
    return 0
  fi
  tty_path=${CODYSSEY_TTY_PATH:-/dev/tty}
  tty_state=
  if { true <"$tty_path"; } 2>/dev/null; then
    tty_state=$(stty -g <"$tty_path")
    stty -echo <"$tty_path"
    printf 'Tailscale auth key or install/up command (blank for browser login): ' >"$tty_path"
    IFS= read -r auth_input <"$tty_path" || auth_input=
    restore_tty
    printf '\n' >"$tty_path"
    auth_key=
    if [[ -n $auth_input ]]; then
      auth_key=$(extract_tailscale_auth_key "$auth_input") || {
        printf 'No complete Tailscale auth key was found.\n' >&2
        return 1
      }
    fi
  else
    printf 'No terminal is available; continuing with Tailscale browser login.\n' >&2
    auth_key=
  fi
  umask 077
  printf 'TS_AUTHKEY=%s\n' "$auth_key" >.env
  chmod 0600 .env
}
