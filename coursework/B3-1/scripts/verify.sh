#!/bin/sh
set -eu
mode=${1:-docker}
case "$mode" in
  --help) printf 'Usage: sh scripts/verify.sh [docker|vm|all]\n'; exit 0 ;;
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker) server=web ;;
  vm) server=vm ;;
  *) printf 'Unknown verification mode\n' >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="network-lab-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile vm --profile verify "$@"; }
trap 'compose down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
compose build "$server" verify
compose up -d --wait --wait-timeout 180 cloud "$server"
compose run --rm --no-deps -e "WEB_URL=http://$server:8080" -e "VERIFY_MODE=$mode" verify
