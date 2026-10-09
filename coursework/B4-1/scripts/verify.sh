#!/bin/sh
set -eu
mode=${1:-docker}
case "$mode" in
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker|vm) ;;
  --help) printf '%s\n' 'Usage: sh scripts/verify.sh [docker|vm|all]'; exit 0 ;;
  *) printf 'Unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="b4-1-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile vm "$@"; }
cleanup() { compose down --volumes --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
docker version >/dev/null
docker compose version
compose config --quiet
if [ "$mode" = docker ]; then
  compose build test
  compose run --rm test
  printf 'DOCKER-VERIFY-SUCCESS (synthetic target only)\n'
else
  compose build vm
  output=$(compose run --rm vm 2>&1 | tr -d '\r')
  printf '%s\n' "$output"
  printf '%s\n' "$output" | grep -q '^VM-LAB-SUCCESS$'
  if printf '%s\n' "$output" | grep -q '^VM-LAB-FAILURE:'; then exit 1; fi
  printf 'VM-VERIFY-SUCCESS (synthetic target, genuine OS controls)\n'
fi
