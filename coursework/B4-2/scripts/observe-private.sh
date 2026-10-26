#!/bin/sh
set -eu
umask 077
test "$#" -eq 2 || { echo "Usage: $0 INPUT_ZIP PRIVATE_EVIDENCE_DIR" >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/private-paths.sh"
prepare_private_paths "$root" "$1" "$2"
run_id=${run_dir##*/}
input_digest=$(sha256sum "$input")
input_digest=${input_digest%% *}
image=b4-2-private-observer:local
container="b4-2-private-$$"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
docker build -f "$root/verify/private/Dockerfile" -t "$image" "$root"
docker create --name "$container" \
  --network none \
  --tmpfs /tmp:rw,nosuid,nodev,size=384m \
  --memory 1g \
  --cpus 1.0 \
  --pids-limit 256 \
  --cap-drop ALL \
  --cap-add DAC_OVERRIDE \
  --security-opt no-new-privileges \
  --env PRIVATE_RUN_ID="$run_id" \
  --env PRIVATE_INPUT_SHA256="$input_digest" \
  "$image" >/dev/null
docker cp "$input" "$container:/private-input/input.zip"
raw_log="$run_dir/serial.raw.log"
normalized_log="$run_dir/serial.log"
set +e
timeout --signal=TERM --kill-after=15s 300s docker start -a "$container" >"$raw_log" 2>&1
command_status=$?
set -e
tr -d '\r' <"$raw_log" >"$normalized_log"
if ! sh "$root/bin/check-private-result.sh" "$normalized_log" "$command_status" "$run_id" "$input_digest" >/dev/null; then
  echo "Private observation command or evidence validation failed (status=$command_status); inspect: $normalized_log" >&2
  exit 1
fi
echo "PRIVATE-OBSERVE-SUCCESS run=$run_dir raw=$raw_log normalized=$normalized_log"
