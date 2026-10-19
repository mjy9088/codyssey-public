#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
cd "$root"
. "$root/lib/preparation.sh"

if (( $# == 0 )); then
  command=(bash)
else
  command=("$@")
fi

if [[ ${command[0]} == bash || ${command[0]} == zellij ]] && docker compose ps --status running --services | grep -qx tailscale; then
  if ! docker compose exec -T tailscale sh -c 'command -v bash && command -v mise && command -v zellij' >/dev/null 2>&1; then
    printf 'Rebuilding the Tailscale service to add terminal tools...\n'
    run_quiet_step "Updating terminal tools" docker compose build tailscale
    run_quiet_step "Restarting terminal service" docker compose up -d --no-deps --force-recreate tailscale
  fi
fi

if [[ -t 0 && -t 1 ]]; then
  exec docker compose exec tailscale "${command[@]}"
fi
exec docker compose exec -T tailscale "${command[@]}"
