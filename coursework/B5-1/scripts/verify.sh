#!/bin/sh
set -eu
mode=${1:-docker}
test "$#" -le 1 || { printf 'Too many arguments\n' >&2; exit 2; }
case "$mode" in
  --help)
    printf '%s\n' 'Usage: sh scripts/verify.sh [docker|vm|all]' \
      'Requires Docker Engine, Compose v2, and a POSIX shell.'
    exit 0 ;;
  docker|vm|all) ;;
  *) printf 'Unknown verification mode: %s\n' "$mode" >&2; exit 2 ;;
esac
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
project=
temporary=$(mktemp -d)
child=

compose() {
  exec docker compose -p "$project" -f "$root/compose.yaml" --profile verify --profile vm "$@"
}
run_compose() {
  # Waiting for an asynchronous child lets the shell act on a signal immediately.
  compose "$@" <&3 &
  child=$!
  if wait "$child"; then status=0; else status=$?; fi
  child=
  return "$status"
} 3<&0
cleanup_project() {
  if [ -n "$project" ]; then
    (compose down --volumes --remove-orphans --rmi local) >/dev/null 2>&1 || true
    project=
  fi
}
cleanup() {
  cleanup_project
  rm -rf -- "$temporary"
}
stop() {
  trap '' INT TERM
  if [ -n "$child" ]; then
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" || true
  fi
  exit "$1"
}
trap cleanup EXIT
trap 'stop 130' INT
trap 'stop 143' TERM
verify_docker() {
  project="mini-redis-docker-$$"
  run_compose config --quiet
  run_compose build test mini-redis
  run_compose run --rm -T test
  printf '%s\n' 'CONFIG SET maxmemory 30' 'SET user:1 "Alice Example"' \
    'GET user:1' 'INFO memory' quit >"$temporary/commands"
  run_compose run --rm -T mini-redis <"$temporary/commands" >"$temporary/transcript"
  cat "$temporary/transcript"
  grep -Fxq '"Alice Example"' "$temporary/transcript"
  grep -Fxq 'used_memory:19' "$temporary/transcript"
  printf 'DOCKER-VERIFY-SUCCESS\n'
}
verify_vm() {
  project="mini-redis-vm-$$"
  run_compose config --quiet
  run_compose build vm
  vm_status=0
  run_compose run --rm -T vm >"$temporary/vm" 2>&1 || vm_status=$?
  tr -d '\r' <"$temporary/vm" >"$temporary/transcript"
  cat "$temporary/transcript"
  test "$vm_status" -eq 0 || exit "$vm_status"
  grep -Fxq 'VM-TEST-SUCCESS' "$temporary/transcript"
  if grep -q '^VM-TEST-FAILURE:' "$temporary/transcript"; then exit 1; fi
  printf 'VM-VERIFY-SUCCESS\n'
}

docker version >/dev/null
docker compose version
case "$mode" in
  docker) verify_docker ;;
  vm) verify_vm ;;
  all)
    verify_docker
    cleanup_project
    verify_vm
    ;;
esac
