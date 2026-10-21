#!/bin/sh
set -eu
mode=${1:-docker}
test "$#" -le 1 || { printf 'Too many arguments\n' >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
case "$mode" in
  --help) printf '%s\n' 'Usage: sh scripts/verify.sh [docker|vm|all]'; exit 0 ;;
  all | docker | vm) ;;
  *) printf 'Unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac

run_browser() {
  run_mode=$1
  server=$2
  project="folio-lending-$run_mode-$$"
  compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile verify --profile vm "$@"; }
  cleanup() { compose down --volumes --remove-orphans >/dev/null 2>&1 || true; }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  docker version >/dev/null
  compose config --quiet
  compose build "$server" verify
  compose up -d --wait --wait-timeout 240 "$server"
  compose run --rm --no-deps -e "BASE_URL=http://$server:8000" verify
  if [ "$run_mode" = vm ]; then
    compose exec -T vm wget -q -O - http://127.0.0.1:8000/__vm-proof
  fi
  cleanup
  trap - EXIT INT TERM
}

case "$mode" in
  docker) sh "$root/scripts/check.sh"; run_browser docker app ;;
  vm) run_browser vm vm ;;
  all) sh "$root/scripts/check.sh"; run_browser docker app; run_browser vm vm ;;
esac
