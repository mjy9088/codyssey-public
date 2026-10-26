#!/bin/sh
set -eu
umask 077
test "$#" -eq 2 || { printf 'Usage: %s INPUT_ZIP PRIVATE_EVIDENCE_DIR\n' "$0" >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/private-paths.sh"
prepare_private_paths "$root" "$1" "$2"
image="b4-1-private-vm:local"
container="b4-1-private-$$"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
docker build -f "$root/verify/private/Dockerfile" -t "$image" "$root"
docker create --name "$container" \
  --network none \
  --tmpfs /tmp:rw,nosuid,nodev,size=384m \
  --memory 1536m \
  --cpus 1.0 \
  --pids-limit 256 \
  --cap-drop ALL \
  --cap-add DAC_OVERRIDE \
  --security-opt no-new-privileges \
  "$image" >/dev/null
docker cp "$input" "$container:/private-input/input.zip"
raw_log=$run_dir/serial.raw.log
normalized_log=$run_dir/serial.log
set +e
timeout --signal=TERM --kill-after=15s 180s docker start -a "$container" >"$raw_log" 2>&1
command_status=$?
set -e
tr -d '\r' <"$raw_log" >"$normalized_log"
if test "$command_status" -ne 0 || ! grep -q '^PRIVATE-VM-SUCCESS$' "$normalized_log" || grep -q '^PRIVATE-VM-FAILURE:' "$normalized_log"; then
  printf 'Private verification failed (status=%s); inspect: %s\n' "$command_status" "$normalized_log" >&2
  exit 1
fi
printf 'PRIVATE-VERIFY-SUCCESS run=%s raw=%s normalized=%s\n' "$run_dir" "$raw_log" "$normalized_log"
