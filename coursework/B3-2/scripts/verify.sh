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
project="ai-review-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile verify --profile vm "$@"; }
cleanup() { compose down --volumes --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
docker version >/dev/null
docker compose version
compose config --quiet
if [ "$mode" = docker ]; then
  compose build test reviewer
  compose run --rm test
  output=$(compose run --rm reviewer pr)
  printf '%s\n' "$output"
  printf '%s\n' "$output" | grep -q '^\[INFO\] api_requests=0$'
  printf '%s\n' "$output" | grep -q '^## How to Test$'
  if compose run --rm reviewer commit --backend api >/dev/null 2>&1; then exit 1; fi
  printf 'DOCKER-VERIFY-SUCCESS\n'
else
  compose build vm
  output=$(compose run --rm vm 2>&1 | tr -d '\r')
  printf '%s\n' "$output"
  printf '%s\n' "$output" | grep -q '^VM-TEST-SUCCESS$'
  if printf '%s\n' "$output" | grep -q '^VM-TEST-FAILURE:'; then exit 1; fi
  printf 'VM-VERIFY-SUCCESS\n'
fi
