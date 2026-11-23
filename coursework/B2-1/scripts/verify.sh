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
sh "$root/verify/test-source-contract.sh" "$root"
project="ledger-$mode-$$"
compose() { docker compose -p "$project" -f "$root/compose.yaml" "$@"; }
vm_log=
cleanup() {
  [ -z "$vm_log" ] || rm -f "$vm_log"
  compose --profile verify --profile vm down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker version >/dev/null
docker compose version
compose config --quiet
if [ "$mode" = docker ]; then
  compose --profile verify build verify
  compose --profile verify run --rm verify
else
  compose --profile vm build vm
  vm_log=$(mktemp)
  status=0
  compose --profile vm run --rm -T --no-deps vm >"$vm_log" 2>&1 || status=$?
  cat "$vm_log"
  if [ "$status" -ne 0 ]; then
    printf 'QEMU verification exited with status %s.\n' "$status" >&2
    exit "$status"
  fi
  if ! grep -Eq '^VM-BOOT-READY kernel=[^[:space:]]+[[:space:]]*$' "$vm_log" ||
     ! grep -Eq '^VM-TEST-PASS[[:space:]]*$' "$vm_log" ||
     grep -q '^VM-TEST-FAIL:' "$vm_log"; then
    printf 'Missing successful guest boot and test completion proof.\n' >&2
    exit 1
  fi
fi
