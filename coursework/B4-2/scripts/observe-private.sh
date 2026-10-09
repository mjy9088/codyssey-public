#!/bin/sh
set -eu
umask 077
test "$#" -eq 2 || { echo "Usage: $0 INPUT_ZIP PRIVATE_EVIDENCE_DIR" >&2; exit 2; }
input_arg=$1
evidence_arg=$2
test -f "$input_arg" || { echo "Input ZIP not found: $input_arg" >&2; exit 2; }
test ! -L "$input_arg" || { echo 'Input ZIP must not be a symlink' >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
public_root=$root
ancestor=$root
while test "$ancestor" != /; do
  if test -e "$ancestor/.git"; then
    public_root=$ancestor
    break
  fi
  ancestor=$(dirname "$ancestor")
done
input=$(realpath "$input_arg")
case "$input" in "$public_root"|"$public_root"/*) echo 'Input ZIP must remain outside the public checkout' >&2; exit 2 ;; esac
if test -e "$evidence_arg"; then
  test -d "$evidence_arg" && test ! -L "$evidence_arg" || { echo 'Evidence root must be a real directory, not a symlink' >&2; exit 2; }
else
  mkdir -m 0700 -p "$evidence_arg"
fi
evidence=$(realpath "$evidence_arg")
case "$evidence" in "$public_root"|"$public_root"/*) echo 'Evidence root must remain outside the public checkout' >&2; exit 2 ;; esac
chmod 0700 "$evidence"
run_dir=$(mktemp -d "$evidence/run.XXXXXX")
chmod 0700 "$run_dir"
size=$(wc -c <"$input")
test "$size" -le 52428800 || { echo 'Input ZIP exceeds 50 MiB safety bound' >&2; exit 2; }
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
  "$image" >/dev/null
docker cp "$input" "$container:/private-input/input.zip"
raw_log="$run_dir/serial.raw.log"
normalized_log="$run_dir/serial.log"
set +e
timeout --signal=TERM --kill-after=15s 300s docker start -a "$container" >"$raw_log" 2>&1
command_status=$?
set -e
tr -d '\r' <"$raw_log" >"$normalized_log"
if ! sh "$root/bin/check-private-result.sh" "$normalized_log" "$command_status" >/dev/null; then
  echo "Private observation command or evidence validation failed (status=$command_status); inspect: $normalized_log" >&2
  exit 1
fi
echo "PRIVATE-OBSERVE-SUCCESS run=$run_dir raw=$raw_log normalized=$normalized_log"
