#!/usr/bin/env zsh
set -eu
setopt pipe_fail

root=${0:A:h}
cd "$root"
. "$root/lib/auth.sh"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

mise trust "$root/mise.toml"
mise install just@1.43.0
eval "$(mise env -s zsh)"

restore_tty() {
  if [[ -n ${tty_state:-} ]]; then
    stty "$tty_state" <"$tty_path" 2>/dev/null || true
    tty_state=
  fi
}

if [[ -z ${TS_AUTHKEY+x} && ! -e .env ]]; then
  tty_path=${CODYSSEY_TTY_PATH:-/dev/tty}
  if { true <"$tty_path"; } 2>/dev/null; then
    tty_state=$(stty -g <"$tty_path")
    trap restore_tty EXIT
    trap 'restore_tty; exit 129' HUP
    trap 'restore_tty; exit 130' INT
    trap 'restore_tty; exit 143' TERM
    printf 'Tailscale auth key or install/up command (blank for browser login): ' >"$tty_path"
    stty -echo <"$tty_path"
    IFS= read -r auth_input <"$tty_path" || auth_input=
    restore_tty
    trap - EXIT HUP INT TERM
    printf '\n' >"$tty_path"
    auth_key=
    if [[ -n $auth_input ]]; then
      auth_key=$(extract_tailscale_auth_key "$auth_input") || {
        printf 'No complete Tailscale auth key was found.\n' >&2
        exit 1
      }
    fi
  else
    printf 'No terminal is available; continuing with Tailscale browser login.\n' >&2
    auth_key=
  fi
  umask 077
  printf 'TS_AUTHKEY=%s\n' "$auth_key" >.env
  chmod 0600 .env
fi

docker compose up -d --build

tailnet_state=
for _ in {1..90}; do
  running=$(docker compose ps --status running --services 2>/dev/null || true)
  if print -r -- "$running" | grep -qx tailscale \
    && print -r -- "$running" | grep -qx gost \
    && print -r -- "$running" | grep -qx gost-ui; then
    tailscale_status=$(docker compose exec -T tailscale tailscale status --json 2>/dev/null || true)
    if print -r -- "$tailscale_status" | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
      tailnet_state=running
      break
    fi
    if print -r -- "$tailscale_status" | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"NeedsLogin"'; then
      tailnet_state=needs-login
      break
    fi
  fi
  sleep 1
done

if [[ -z $tailnet_state ]]; then
  printf 'Services did not become ready. Run: docker compose logs tailscale gost gost-ui\n' >&2
  exit 1
fi

if [[ $tailnet_state == needs-login ]]; then
  auth_url=
  # NeedsLogin can precede the control server's authentication URL, especially
  # while a software-emulated VM is still starting its network services.
  for _ in {1..60}; do
    login_output=$(docker compose logs --no-color tailscale 2>/dev/null || true)
    auth_url=$(print -r -- "$login_output" | grep -Eo 'https://login\.tailscale\.com/[A-Za-z0-9_./?=&-]+' | head -n 1 || true)
    [[ -z $auth_url ]] || break
    sleep 1
  done
  if [[ -z $auth_url ]]; then
    printf 'Tailscale needs login, but no authentication URL is available yet. Run: docker compose logs tailscale\n' >&2
    exit 1
  fi
  printf 'Tailscale is not connected yet. Authenticate at: %s\n' "$auth_url"
  if [[ ${CODYSSEY_OPEN_BROWSER:-1} != 0 ]] && command -v open >/dev/null 2>&1; then
    open "$auth_url" 2>/dev/null || true
  fi
fi

ui_url='http://localhost:18081/?api=http%3A%2F%2Flocalhost%3A18080'
ui_ready=0
for _ in {1..60}; do
  if curl --silent --fail --output /dev/null "$ui_url"; then
    ui_ready=1
    break
  fi
  sleep 1
done
if (( ui_ready != 1 )); then
  printf 'GOST UI did not become ready: %s\n' "$ui_url" >&2
  exit 1
fi

printf 'GOST UI: %s\n' "$ui_url"
if [[ ${CODYSSEY_OPEN_BROWSER:-1} != 0 ]] && command -v open >/dev/null 2>&1; then
  open -a 'Google Chrome' "$ui_url" 2>/dev/null || open "$ui_url" 2>/dev/null || true
fi
