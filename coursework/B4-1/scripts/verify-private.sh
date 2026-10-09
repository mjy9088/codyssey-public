#!/bin/sh
set -eu
test "$#" -eq 2 || { printf 'Usage: %s INPUT_ZIP PRIVATE_EVIDENCE_DIR\n' "$0" >&2; exit 2; }
input=$1
evidence=$2
test -f "$input" || { printf 'Input ZIP not found: %s\n' "$input" >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image="b4-1-private-vm:local"
container="b4-1-private-$$"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
mkdir -p "$evidence"
docker build -f "$root/verify/private/Dockerfile" -t "$image" "$root"
docker create --name "$container" --tmpfs /tmp:rw,nosuid,nodev,size=128m \
  --security-opt no-new-privileges "$image" >/dev/null
docker cp "$input" "$container:/private-input/input.zip"
if docker start -a "$container" 2>&1 | tr -d '\r' | tee "$evidence/private-app-vm.log"; then
  result=0
else
  result=$?
fi
grep -q '^PRIVATE-VM-SUCCESS$' "$evidence/private-app-vm.log"
if grep -q '^PRIVATE-VM-FAILURE:' "$evidence/private-app-vm.log"; then exit 1; fi
printf 'PRIVATE-VERIFY-SUCCESS evidence=%s\n' "$evidence/private-app-vm.log"
exit "$result"
