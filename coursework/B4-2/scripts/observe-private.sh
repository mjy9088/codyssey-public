#!/bin/sh
set -eu
umask 077
test "$#" -eq 2 || { echo "Usage: $0 INPUT_ZIP PRIVATE_EVIDENCE_DIR" >&2; exit 2; }
input_arg=$1
evidence_arg=$2
case "$input_arg" in /*) ;; *) echo 'Input ZIP path must be absolute' >&2; exit 2 ;; esac
case "$evidence_arg" in /*) ;; *) echo 'Evidence root path must be absolute' >&2; exit 2 ;; esac
path_has_symlink() {
  path=$1
  current=
  old_ifs=$IFS
  IFS=/
  set -f
  set -- $path
  set +f
  IFS=$old_ifs
  for component do
    test -n "$component" || continue
    current=$current/$component
    test ! -L "$current" || return 0
  done
  return 1
}
test -f "$input_arg" || { echo "Input ZIP not found: $input_arg" >&2; exit 2; }
if path_has_symlink "$input_arg"; then echo 'Input ZIP path must not contain symlinks' >&2; exit 2; fi
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
case "$input" in
  "$public_root/.local/B4-2/agent-app-leak.zip") ;;
  "$public_root"|"$public_root"/*) echo 'Input ZIP must remain outside the public checkout except at .local/B4-2/agent-app-leak.zip' >&2; exit 2 ;;
esac
size=$(wc -c <"$input")
test "$size" -le 52428800 || { echo 'Input ZIP exceeds 50 MiB safety bound' >&2; exit 2; }
if path_has_symlink "$evidence_arg"; then echo 'Evidence root path must not contain symlinks' >&2; exit 2; fi
evidence=$(realpath -m "$evidence_arg")
case "$evidence" in
  "$public_root/.local/evidence/B4-2") ;;
  "$public_root"|"$public_root"/*) echo 'Evidence root must remain outside the public checkout except at .local/evidence/B4-2' >&2; exit 2 ;;
esac
if test -e "$evidence"; then
  test -d "$evidence" || { echo 'Evidence root must be a directory' >&2; exit 2; }
else
  mkdir -m 0700 -p "$evidence"
fi
chmod 0700 "$evidence"
run_dir=$(mktemp -d "$evidence/run.XXXXXX")
chmod 0700 "$run_dir"
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
