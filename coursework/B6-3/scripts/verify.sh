#!/bin/sh
set -eu
mode=${1:-docker}
case "$mode" in
  --help) printf '%s\n' 'Usage: sh scripts/verify.sh [docker|vm|all]'; exit 0 ;;
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker) server=app ;;
  vm) server=vm ;;
  *) printf 'Unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="folio-lending-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile verify --profile vm "$@"; }
cleanup() { compose down --volumes --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
docker version >/dev/null
compose config --quiet
compose build "$server" verify
compose up -d --wait --wait-timeout 240 "$server"
compose run --rm --no-deps -e "BASE_URL=http://$server:8000" verify
if [ "$mode" = vm ]; then
  compose exec -T vm wget -q -O - http://127.0.0.1:8000/__vm-proof
fi
