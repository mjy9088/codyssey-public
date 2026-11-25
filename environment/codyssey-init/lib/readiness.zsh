#!/usr/bin/env zsh

check_tunnel_upgrade() {
  local containers name control
  if ! containers=$(docker container ls --all --filter 'name=^/tailnet-forward-(gost|ui)$' \
      --format '{{.Names}} {{.Label "org.codyssey.tunnel-control"}}' 2>/dev/null); then
    printf 'Cannot check for legacy GOST containers. Make the selected Docker engine reachable and retry.\n' >&2
    return 1
  fi
  while read -r name control; do
    if [[ $name == tailnet-forward-ui || ( $name == tailnet-forward-gost && $control != unix-v1 ) ]]; then
      printf 'Legacy GOST containers found. Save pending changes in the old UI and run docker compose down with the old Compose file before retrying.\n' >&2
      return 1
    fi
  done <<< "$containers"
}

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
  printf 'Services did not become ready. Run: docker compose logs tailscale gost tunnel-ui\n' >&2
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

wait_for_tunnel_ui() {
  local running
  for _ in {1..60}; do
    running=$(docker compose ps --status running --services 2>/dev/null || true)
    if print -r -- "$running" | grep -qx gost \
      && print -r -- "$running" | grep -qx tunnel-ui \
      && curl --noproxy '*' --silent --fail --max-time 4 --output /dev/null "${ui_url}health"; then
      return 0
    fi
    sleep 1
  done
  printf 'Codyssey tunnels did not become ready: %s\n' "$ui_url" >&2
  return 1
}
