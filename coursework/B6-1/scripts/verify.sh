#!/bin/sh
set -eu

mode=${1:-docker}
test "$#" -le 1 || { printf 'Too many arguments\n' >&2; exit 2; }
case "$mode" in
  --help) printf '%s\n' 'Usage: sh scripts/verify.sh [docker|vm|all]'; exit 0 ;;
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker|vm) ;;
  *) printf 'Unknown verification mode: %s\n' "$mode" >&2; exit 2 ;;
esac

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="library-sql-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" "$@"; }
cleanup() { compose --profile vm down --volumes --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

docker version >/dev/null
docker compose version
compose --profile vm config --quiet
case "$mode" in
  docker)
    compose build check
    compose run --rm check ;;
  vm)
    compose --profile vm build vm
    output=$(compose --profile vm run --rm vm 2>&1)
    printf '%s\n' "$output"
    printf '%s\n' "$output" | grep -q 'VM-CHECK-PASS'
    printf '%s\n' "$output" | grep -q 'SQL-CHECK-PASS' ;;
esac
printf 'Verification mode=%s passed\n' "$mode"
