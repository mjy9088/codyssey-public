#!/usr/bin/env zsh
set -eu
setopt pipe_fail

root=${0:A:h}
cd "$root"
. "$root/lib/auth.sh"
. "$root/lib/preparation.sh"
. "$root/lib/readiness.zsh"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

prepared=0
if (( $# == 1 )) && [[ $1 == --prepared ]]; then
  prepared=1
elif (( $# != 0 )); then
  printf 'Usage: zsh next-script.zsh [--prepared]\n' >&2
  exit 2
fi

if (( prepared == 0 )); then
  trap finish_startup EXIT
  trap 'interrupt_startup 129' HUP
  trap 'interrupt_startup 130' INT
  trap 'interrupt_startup 143' TERM
  printf 'codyssey-init: starting background preparation.\n'
  start_startup_preparation "$root"
fi

open_browser() {
  local url=$1
  if [[ $(uname -s) == Darwin && ${CODYSSEY_BROWSER:-portable} != system ]]; then
    bash "$root/scripts/tailnet-browser.sh" "$url"
  elif [[ $url == https://login.tailscale.com/* ]]; then
    open "$url"
  else
    open -a 'Google Chrome' "$url" 2>/dev/null || open "$url"
  fi
}

if (( prepared == 0 )); then
  configure_tailscale_auth
  printf 'codyssey-init: waiting for preparation.\n'
  wait_startup_preparation
  printf 'codyssey-init: preparation complete.\n'
fi
eval "$(mise env -s zsh)"
docker compose up -d --no-build
wait_for_tailnet

if [[ $tailnet_state == needs-login ]]; then
  find_tailscale_auth_url
  printf 'Tailscale is not connected yet. Authenticate at: %s\n' "$auth_url"
  if [[ ${CODYSSEY_OPEN_BROWSER:-1} != 0 ]] && command -v open >/dev/null 2>&1; then
    open_browser "$auth_url" || printf 'Could not launch the browser; use the printed login URL.\n' >&2
  fi
fi

ui_url='http://localhost:18081/?api=http%3A%2F%2Flocalhost%3A18080'
wait_for_gost_ui

printf 'GOST UI: %s\n' "$ui_url"
printf 'Chrome extension: %s/chrome-extension (Load unpacked at chrome://extensions).\n' "$root"
if [[ ${CODYSSEY_OPEN_BROWSER:-1} != 0 ]] && command -v open >/dev/null 2>&1; then
  open_browser "$ui_url" || printf 'Could not launch the browser; use the printed GOST URL.\n' >&2
fi

if [[ -t 0 && -t 1 && ${CODYSSEY_INTERACTIVE_SHELL:-1} != 0 ]]; then
  printf 'Environment ready. Use just to enter the Tailscale container.\n'
  exec zsh -i
fi
