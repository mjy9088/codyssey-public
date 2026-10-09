#!/usr/bin/env bash

extract_tailscale_auth_key() {
  local input=$1 key
  key=$(printf '%s\n' "$input" | grep -Eo "tskey-auth-[^[:space:]'\"]+" | head -n 1 || true)
  [[ $key =~ ^tskey-auth-[A-Za-z0-9_-]+$ ]] || return 1
  printf '%s\n' "$key"
}
