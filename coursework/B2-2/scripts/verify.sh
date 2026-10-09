#!/bin/sh
set -eu
mode=${1:-docker}
case "$mode" in
  --help) printf 'Usage: sh scripts/verify.sh [docker|vm|all]\n'; exit 0 ;;
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker|vm) ;;
  *) printf 'Unknown verification mode\n' >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="collaboration-lab-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile vm "$@"; }
trap 'compose down --volumes --remove-orphans >/dev/null 2>&1 || true' EXIT
case "$mode" in
  docker) compose build check; compose run --rm check ;;
  vm)
    compose build vm
    if result=$(compose run --rm vm 2>&1); then status=0; else status=$?; fi
    printf '%s\n' "$result"
    test "$status" -eq 0
    printf '%s\n' "$result" | tr -d '\r' | grep -q '^VM-CHECK-PASS$'
    ;;
esac
printf 'PASS: %s verification completed\n' "$mode"
