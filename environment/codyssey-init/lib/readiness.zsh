#!/usr/bin/env zsh

read_tailnet_backend() {
  local backend_json
  backend_json=$(docker compose exec -T tailscale tailscale status --json 2>/dev/null || true)
  if print -r -- "$backend_json" | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
    print -r -- running
  elif print -r -- "$backend_json" | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"NeedsLogin"'; then
    print -r -- needs-login
  fi
}

wait_for_tailnet() {
  local running
  tailnet_state=
  for _ in {1..90}; do
    running=$(docker compose ps --status running --services 2>/dev/null || true)
    if print -r -- "$running" | grep -qx tailscale; then
      tailnet_state=$(read_tailnet_backend)
      [[ -z $tailnet_state ]] || return 0
    fi
    sleep 1
  done
  printf 'Services did not become ready. Run: docker compose logs tailscale gost gost-ui\n' >&2
  return 1
}

find_tailscale_auth_url() {
  local login_status login_output
  auth_url=
  for _ in {1..60}; do
    login_status=$(docker compose exec -T tailscale tailscale status --json 2>/dev/null || true)
    auth_url=$(print -r -- "$login_status" | sed -n 's/.*"AuthURL"[[:space:]]*:[[:space:]]*"\(https:\/\/login\.tailscale\.com\/[^" ]*\)".*/\1/p')
    [[ -z $auth_url ]] || return 0
    login_output=$(docker compose logs --no-color tailscale 2>/dev/null || true)
    auth_url=$(print -r -- "$login_output" | grep -Eo 'https://login\.tailscale\.com/[A-Za-z0-9_./?=&-]+' | tail -n 1 || true)
    [[ -z $auth_url ]] || return 0
    sleep 1
  done
  printf 'Tailscale needs login, but no authentication URL is available yet. Run: docker compose logs tailscale\n' >&2
  return 1
}

wait_for_gost_ui() {
  local running
  for _ in {1..60}; do
    running=$(docker compose ps --status running --services 2>/dev/null || true)
    if print -r -- "$running" | grep -qx gost \
      && print -r -- "$running" | grep -qx gost-ui \
      && curl --silent --fail --output /dev/null 'http://localhost:18080/config' \
      && curl --silent --fail --output /dev/null "$ui_url"; then
      return 0
    fi
    sleep 1
  done
  printf 'GOST API/UI did not become ready: %s\n' "$ui_url" >&2
  return 1
}
