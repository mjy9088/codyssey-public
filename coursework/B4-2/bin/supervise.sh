#!/bin/sh
set -eu
test "$#" -ge 5 || { echo "Usage: $0 MARKER DEADLINE GRACE -- COMMAND..." >&2; exit 2; }
marker=$1
deadline=$2
grace=$3
shift 3
test "$1" = -- || { echo 'Missing -- before command' >&2; exit 2; }
shift
test ! -e "$marker" || { echo "Supervisor marker already exists: $marker" >&2; exit 2; }
umask 077
"$@" &
child=$!
(
  sleep "$deadline"
  if kill -0 "$child" 2>/dev/null; then
    state=$(awk '{ rest=$0; sub(/^[0-9]+ \(.*\) /, "", rest); print substr(rest, 1, 1) }' "/proc/$child/stat" 2>/dev/null || true)
    if test "$state" != Z && test -n "$state"; then
      printf 'SUPERVISOR-DEADLINE pid=%s seconds=%s\n' "$child" "$deadline" >"$marker"
      kill -TERM "$child" 2>/dev/null || true
      sleep "$grace"
      kill -KILL "$child" 2>/dev/null || true
    fi
  fi
) &
watchdog=$!
set +e
wait "$child"
status=$?
set -e
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
exit "$status"
