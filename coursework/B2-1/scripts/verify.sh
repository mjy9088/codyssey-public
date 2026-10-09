#!/bin/sh
set -eu

mode=${1:-docker}
test "$#" -le 1 || { echo "too many arguments" >&2; exit 2; }
case "$mode" in
  --help) echo "Usage: sh scripts/verify.sh [docker|vm|all]"; exit 0 ;;
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker|vm) ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="ledger-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" "$@"; }
cleanup() { compose --profile verify --profile vm down --volumes --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

docker version >/dev/null
docker compose version
compose config --quiet
if [ "$mode" = docker ]; then
  compose --profile verify build verify
  compose --profile verify run --rm verify
else
  compose --profile vm build vm
  compose --profile vm up -d --wait --wait-timeout 180 vm
  compose --profile vm logs --no-color vm
  result=$(compose --profile vm exec -T vm wget -q -O - http://127.0.0.1:8080/result.json)
  printf '%s\n' "$result"
  printf '%s' "$result" | grep -q '"status":"pass"'
fi
