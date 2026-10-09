#!/bin/sh
set -eu
mode=${1:-docker}
case "$mode" in
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker|vm) ;;
  --help) echo 'Usage: sh scripts/verify.sh [docker|vm|all]'; exit 0 ;;
  *) echo "Unknown mode: $mode" >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="b4-2-$mode-$$"
output_file=
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile vm "$@"; }
cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  test -z "$output_file" || rm -f "$output_file"
}
trap cleanup EXIT INT TERM
docker version >/dev/null
docker compose version
compose config --quiet
if test "$mode" = docker; then
  compose build lab
  workload_timeout=60
  service=lab
else
  compose build vm
  workload_timeout=120
  service=vm
fi
output_file=$(mktemp)
set +e
timeout --signal=TERM --kill-after=10s "${workload_timeout}s" \
  docker compose -p "$project" -f "$root/compose.yaml" --profile vm run --rm "$service" \
  >"$output_file" 2>&1
run_status=$?
set -e
if test "$run_status" -ne 0; then
  printf 'WORKLOAD-FAILURE: mode=%s status=%s bound=%ss\n' "$mode" "$run_status" "$workload_timeout" >&2
  cat "$output_file" >&2
  exit "$run_status"
fi
output=$(tr -d '\r' <"$output_file")
printf '%s\n' "$output"
printf '%s\n' "$output" | grep -q '^MEMORY-CHECK '
printf '%s\n' "$output" | grep -q '^CPU-CHECK '
printf '%s\n' "$output" | grep -q '^DEADLOCK-CHECK '
printf '%s\n' "$output" | grep -q '^SYNTHETIC-LAB-SUCCESS$'
if test "$mode" = vm; then
  printf '%s\n' "$output" | grep -q '^VM-LAB-SUCCESS$'
fi
echo "$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')-VERIFY-SUCCESS (synthetic fixture only)"
