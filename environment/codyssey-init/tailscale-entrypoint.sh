#!/usr/bin/env bash
set -euo pipefail

daemon_pid=
login_pid=
dns_pid=
key_file=
cleanup() {
  trap - EXIT TERM INT
  [[ -z $key_file ]] || rm -f "$key_file"
  [[ -z $login_pid ]] || kill "$login_pid" 2>/dev/null || true
  [[ -z $dns_pid ]] || kill "$dns_pid" 2>/dev/null || true
  [[ -z $daemon_pid ]] || kill "$daemon_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT

mkdir -p /var/run/tailscale
resolver_base=/var/run/tailscale/resolv.conf.base
# Docker may preserve a container's edited resolver across a plain restart.
# Restore bootstrap DNS before the daemon needs to resolve its control server.
if [[ -f $resolver_base ]] && grep -Eq '^nameserver[[:space:]]+100\.100\.100\.100([[:space:]]|$)' /etc/resolv.conf; then
  cat "$resolver_base" > /etc/resolv.conf
else
  cp /etc/resolv.conf "$resolver_base"
fi
state_dir=${TS_STATE_DIR:-/var/lib/tailscale}
umask 077
mkdir -p "$state_dir"
chmod 0700 "$state_dir"
tailscaled --state="$state_dir/tailscaled.state" --statedir="$state_dir" --tun=tailscale0 \
  --socket=/var/run/tailscale/tailscaled.sock \
  --socks5-server=127.0.0.1:1055 &
daemon_pid=$!
ready=0
for ((attempt=0; attempt<60; attempt++)); do
  kill -0 "$daemon_pid" 2>/dev/null || { wait "$daemon_pid"; exit 1; }
  if status=$(tailscale status --json 2>/dev/null) \
    && [[ $(jq -r '.BackendState' <<< "$status") != NoState ]]; then
    ready=1
    break
  fi
  sleep 1
done
[[ $ready == 1 ]] || { printf 'Tailscale daemon did not become ready.\n' >&2; exit 1; }

# Configure only this container's resolver; host-network mode does not make
# Docker's separate resolv.conf inherit the Docker VM's DNS search domains.
(
  while kill -0 "$daemon_pid" 2>/dev/null; do
    bash /usr/local/bin/codyssey-tailnet-dns || printf 'Could not refresh container MagicDNS.\n' >&2
    sleep 5
  done
) &
dns_pid=$!
settings=(--accept-routes=true --accept-dns=true --shields-up=true)
state=$(tailscale status --json | jq -r '.BackendState')
args=()
case $state in
  Running|Starting|Stopped|NeedsMachineAuth)
    # set changes only these preferences; bare up preserves saved hostname,
    # control server, and other user settings when reconnecting this identity.
    tailscale set "${settings[@]}"
    ;;
  *) args=("${settings[@]}") ;;
esac
if (( ${#args[@]} )) && [[ -n ${TS_AUTHKEY:-} ]]; then
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
