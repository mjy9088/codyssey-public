#!/bin/sh
set -eu
mode=${1:-docker}
test "$#" -le 1 || { printf 'Too many arguments\n' >&2; exit 2; }
case "$mode" in
  docker|vm|all|provided|synthetic-docker|synthetic-vm|synthetic-all) ;;
  --help)
    printf '%s\n' \
      'Usage: sh scripts/verify.sh [docker|vm|all|provided|synthetic-docker|synthetic-vm|synthetic-all]' \
      'docker, vm, and all automatically use .local/B4-2/agent-app-leak.zip when it is present.' \
      'provided requires that archive; synthetic-* always runs the publishable fixture.'
    exit 0
    ;;
  *) echo "Unknown mode: $mode" >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
public_root=$root
ancestor=$root
while test "$ancestor" != /; do
  if test -e "$ancestor/.git"; then public_root=$ancestor; break; fi
  ancestor=$(dirname "$ancestor")
done
archive=${B4_PRIVATE_ARCHIVE:-$public_root/.local/B4-2/agent-app-leak.zip}
evidence=${B4_PRIVATE_EVIDENCE_DIR:-$public_root/.local/evidence/B4-2}
case "$mode" in
  synthetic-docker) mode=docker ;;
  synthetic-vm) mode=vm ;;
  synthetic-all) mode=all ;;
  provided)
    test -e "$archive" || test -L "$archive" || {
      printf 'Provided archive not found: %s\n' "$archive" >&2
      exit 2
    }
    exec sh "$root/scripts/observe-private.sh" "$archive" "$evidence"
    ;;
  *)
    if test -e "$archive" || test -L "$archive"; then
      printf 'LOCAL-ARCHIVE-DETECTED path=%s; running isolated supplied-target observation once\n' "$archive"
      exec sh "$root/scripts/observe-private.sh" "$archive" "$evidence"
    fi
    ;;
esac
if test "$mode" = all; then
  sh "$0" synthetic-docker
  exec sh "$0" synthetic-vm
fi
project="b4-2-$mode-$$"
output_file=
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile vm "$@"; }
cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  test -z "$output_file" || rm -f "$output_file"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
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
