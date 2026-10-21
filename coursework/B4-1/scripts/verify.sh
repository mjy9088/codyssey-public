#!/bin/sh
set -eu
mode=${1:-docker}
case "$mode" in
  docker|vm|all|provided|synthetic-docker|synthetic-vm|synthetic-all) ;;
  --help)
    printf '%s\n' \
      'Usage: sh scripts/verify.sh [docker|vm|all|provided|synthetic-docker|synthetic-vm|synthetic-all]' \
      'docker, vm, and all automatically use .local/B4-1/agent-app.zip when it is present.' \
      'provided requires that archive; synthetic-* always runs the publishable fixture.'
    exit 0
    ;;
  *) printf 'Unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
public_root=$root
ancestor=$root
while test "$ancestor" != /; do
  if test -e "$ancestor/.git"; then public_root=$ancestor; break; fi
  ancestor=$(dirname "$ancestor")
done
archive=${B4_PRIVATE_ARCHIVE:-$public_root/.local/B4-1/agent-app.zip}
evidence=${B4_PRIVATE_EVIDENCE_DIR:-$public_root/.local/evidence/B4-1}
case "$mode" in
  synthetic-docker) mode=docker ;;
  synthetic-vm) mode=vm ;;
  synthetic-all) mode=all ;;
  provided)
    test -e "$archive" || test -L "$archive" || {
      printf 'Provided archive not found: %s\n' "$archive" >&2
      exit 2
    }
    exec sh "$root/scripts/verify-private.sh" "$archive" "$evidence"
    ;;
  *)
    if test -e "$archive" || test -L "$archive"; then
      printf 'LOCAL-ARCHIVE-DETECTED path=%s; running isolated supplied-target verification once\n' "$archive"
      exec sh "$root/scripts/verify-private.sh" "$archive" "$evidence"
    fi
    ;;
esac
if test "$mode" = all; then
  sh "$0" synthetic-docker
  exec sh "$0" synthetic-vm
fi
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
