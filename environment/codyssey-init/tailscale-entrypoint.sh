#!/usr/bin/env bash
set -euo pipefail

daemon_pid=
login_pid=
key_file=
cleanup() {
  trap - EXIT TERM INT
  [[ -z $key_file ]] || rm -f "$key_file"
  [[ -z $login_pid ]] || kill "$login_pid" 2>/dev/null || true
  [[ -z $daemon_pid ]] || kill "$daemon_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT

mkdir -p /var/run/tailscale
tailscaled --state=mem: --tun=tailscale0 \
  --socket=/var/run/tailscale/tailscaled.sock \
  --socks5-server=127.0.0.1:1055 &
daemon_pid=$!
ready=0
for ((attempt=0; attempt<60; attempt++)); do
  kill -0 "$daemon_pid" 2>/dev/null || { wait "$daemon_pid"; exit 1; }
  if tailscale status --json >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ $ready == 1 ]] || { printf 'Tailscale daemon did not become ready.\n' >&2; exit 1; }

args=(--accept-routes=true --accept-dns=true --shields-up=true)
if [[ -n ${TS_AUTHKEY:-} ]]; then
  umask 077
  key_file=$(mktemp /var/run/tailscale/auth.XXXXXX)
  printf '%s' "$TS_AUTHKEY" >"$key_file"
  args+=("--auth-key=file:$key_file")
fi
unset TS_AUTHKEY
# Browser authentication may take any amount of time. Do not crashloop and
# invalidate the login URL while the user is completing it.
tailscale up "${args[@]}" &
login_pid=$!
wait -n "$daemon_pid" "$login_pid"
kill -0 "$daemon_pid" 2>/dev/null || exit 1
login_pid=
[[ -z $key_file ]] || rm -f "$key_file"
key_file=
wait "$daemon_pid"
