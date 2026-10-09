#!/bin/sh
set -eu
test "$#" -eq 2 || { echo "Usage: $0 NORMALIZED_LOG COMMAND_STATUS" >&2; exit 2; }
log=$1
status=$2
test -r "$log" || { echo "Private observation log is unreadable: $log" >&2; exit 1; }
case "$status" in *[!0-9]*|'') echo "Invalid command status: $status" >&2; exit 2 ;; esac
if test "$status" -ne 0; then
  echo "Private observation command failed: status=$status" >&2
  exit 1
fi
if grep -Eq '^PRIVATE-(OBSERVATION-BLOCKED|OBSERVATION-FAILURE|VM-FAILURE|CASE-FAILURE):' "$log"; then
  echo 'Private observation emitted a blocked/failure marker' >&2
  exit 1
fi
test "$(grep -Ec '^PRIVATE-OBSERVATION-COMPLETE$' "$log")" -eq 1 || {
  echo 'Private observation requires exactly one completion marker' >&2
  exit 1
}
for name in memory-before memory-after cpu-before cpu-after thread-before thread-after; do
  test "$(grep -Ec "^PRIVATE-CASE-END name=$name .* samples=([2-9]|[1-9][0-9]+) survivors=0$" "$log")" -eq 1 || {
    echo "Private observation requires exactly one case-end marker: $name" >&2
    exit 1
  }
done
echo 'PRIVATE-RESULT-CHECK-SUCCESS'
