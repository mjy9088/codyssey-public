#!/usr/bin/env zsh
set -eu
setopt pipe_fail

root=${0:A:h}
cd "$root"
. "$root/lib/logging.sh"
init_run_log
. "$root/lib/auth.sh"
. "$root/lib/preparation.sh"
. "$root/lib/readiness.zsh"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

prepared=0
result_path=
if (( $# == 1 )) && [[ $1 == --prepared ]]; then
  prepared=1
elif (( $# == 3 )) && [[ $1 == --prepared && $2 == --result && -f $3 && ! -L $3 ]]; then
  prepared=1
  result_path=$3
elif (( $# != 0 )); then
  printf 'Usage: zsh next-script.zsh [--prepared]\n' >&2
  exit 2
fi

trap finish_startup EXIT
trap 'interrupt_startup 129' HUP
trap 'interrupt_startup 130' INT
trap 'interrupt_startup 143' TERM

if (( prepared == 0 )); then
  printf 'Preparing environment…\n'
  start_startup_preparation "$root"
fi

open_browser() {
  local url=$1
  if [[ $url == https://login.tailscale.com/* ]]; then
    open "$url"
  elif [[ $(uname -s) == Darwin && ${CODYSSEY_BROWSER:-portable} != system ]]; then
    bash "$root/scripts/tailnet-browser.sh" "$url"
  else
    open -a 'Google Chrome' "$url" 2>/dev/null || open "$url"
  fi
}

if (( prepared == 0 )); then
  configure_tailscale_auth
  wait_startup_preparation
fi
eval "$(mise env -s zsh)"
service_status=0
check_tunnel_upgrade || exit 1
if run_quiet_step "Starting services" docker compose up -d --no-build; then :; else
  service_status=1
fi
if wait_for_tailnet; then
  if [[ $tailnet_state == running ]]; then log_event tailscale ready;
  else log_event tailscale needs-login; fi
else
  service_status=1
  log_event tailscale failed
fi

if [[ $tailnet_state == needs-login ]]; then
  if find_tailscale_auth_url; then
    printf 'Tailscale is not connected yet. Authenticate at: %s\n' "$auth_url"
    if [[ ${CODYSSEY_OPEN_BROWSER:-1} != 0 ]] && command -v open >/dev/null 2>&1; then
      if open_browser "$auth_url"; then log_event authentication-browser exit=0; else
      browser_status=$?
      log_event authentication-browser "exit=$browser_status"
      printf 'Could not launch the browser; use the printed login URL.\n' >&2
    fi
    fi
  else
    service_status=1
    log_event authentication-url unavailable
  fi
fi

ui_url='http://127.0.0.1:18081/'
if wait_for_tunnel_ui; then
  log_event gost ready
  printf 'Codyssey tunnels: %s\n' "$ui_url"
  if [[ ${CODYSSEY_OPEN_BROWSER:-1} != 0 ]] && command -v open >/dev/null 2>&1; then
    if open_browser "$ui_url"; then log_event gost-browser exit=0; else
      browser_status=$?
      log_event gost-browser "exit=$browser_status"
      printf 'Could not launch the browser; use the printed Codyssey tunnels URL.\n' >&2
    fi
  fi
else
  service_status=1
  log_event gost failed
fi
(( service_status == 0 )) || exit 1
if [[ $tailnet_state == needs-login && $(read_tailnet_backend) == running ]]; then
  tailnet_state=running
  log_event tailscale ready
fi
if [[ $tailnet_state == running ]]; then
  log_event services ready
  printf 'Codyssey tunnels ready. Tailscale connected.\n'
else
  log_event services needs-login
  printf 'Codyssey tunnels ready. Tailscale login pending.\n'
fi
if [[ -n $result_path ]]; then
  printf '%s\n' "$tailnet_state" "$ui_url" "${auth_url:-}" >"$result_path"
fi
if (( prepared )) && [[ ${CODYSSEY_WORKSTATION_INCOMPLETE:-0} == 1 ]]; then
  printf 'Workstation setup is incomplete. See the warnings above for details.\n' >&2
fi
printf 'Run the same init command again to choose setup options.\n'
if [[ -t 0 && -t 1 && ${CODYSSEY_INTERACTIVE_SHELL:-1} != 0 ]]; then
  exec zsh -i
fi
