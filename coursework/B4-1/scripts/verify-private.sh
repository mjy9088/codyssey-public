#!/bin/sh
set -eu
umask 077
test "$#" -eq 2 || { printf 'Usage: %s INPUT_ZIP PRIVATE_EVIDENCE_DIR\n' "$0" >&2; exit 2; }
input_arg=$1
evidence_arg=$2
case "$input_arg" in /*) ;; *) printf 'Input ZIP path must be absolute\n' >&2; exit 2 ;; esac
case "$evidence_arg" in /*) ;; *) printf 'Evidence root path must be absolute\n' >&2; exit 2 ;; esac
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
test -f "$input_arg" || { printf 'Input ZIP not found: %s\n' "$input_arg" >&2; exit 2; }
if path_has_symlink "$input_arg"; then printf 'Input ZIP path must not contain symlinks\n' >&2; exit 2; fi
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
public_root=$root
ancestor=$root
while test "$ancestor" != /; do
  if test -e "$ancestor/.git"; then public_root=$ancestor; break; fi
  ancestor=$(dirname "$ancestor")
done
input=$(realpath "$input_arg")
case "$input" in
  "$public_root/.local/B4-1/agent-app.zip") ;;
  "$public_root"|"$public_root"/*) printf 'Input ZIP must remain outside the public checkout except at .local/B4-1/agent-app.zip\n' >&2; exit 2 ;;
esac
size=$(wc -c <"$input")
test "$size" -le 52428800 || { printf 'Input ZIP exceeds 50 MiB safety bound\n' >&2; exit 2; }
if path_has_symlink "$evidence_arg"; then printf 'Evidence root path must not contain symlinks\n' >&2; exit 2; fi
evidence=$(realpath -m "$evidence_arg")
case "$evidence" in
  "$public_root/.local/evidence/B4-1") ;;
  "$public_root"|"$public_root"/*) printf 'Evidence root must remain outside the public checkout except at .local/evidence/B4-1\n' >&2; exit 2 ;;
esac
if test -e "$evidence"; then
  test -d "$evidence" || { printf 'Evidence root must be a directory\n' >&2; exit 2; }
else
  mkdir -m 0700 -p "$evidence"
fi
chmod 0700 "$evidence"
run_dir=$(mktemp -d "$evidence/run.XXXXXX")
chmod 0700 "$run_dir"
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
