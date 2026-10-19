#!/bin/sh
set -eu
test "$#" -eq 4 || { echo "Usage: $0 NORMALIZED_LOG COMMAND_STATUS RUN_ID INPUT_SHA256" >&2; exit 2; }
log=$1
status=$2
run_id=$3
input_digest=$4
test -r "$log" || { echo "Private observation log is unreadable: $log" >&2; exit 1; }
case "$status" in *[!0-9]*|'') echo "Invalid command status: $status" >&2; exit 2 ;; esac
case "$run_id" in run.*) ;; *) echo "Invalid run identity: $run_id" >&2; exit 2 ;; esac
case "$input_digest" in *[!0-9a-f]*|'') echo 'Invalid input digest' >&2; exit 2 ;; esac
test "${#input_digest}" -eq 64 || { echo 'Invalid input digest' >&2; exit 2; }
if test "$status" -ne 0; then
  echo "Private observation command failed: status=$status" >&2
  exit 1
fi
if grep -Eq '^PRIVATE-(OBSERVATION-BLOCKED|OBSERVATION-FAILURE|VM-FAILURE|CASE-FAILURE):' "$log"; then
  echo 'Private observation emitted a blocked/failure marker' >&2
  exit 1
fi
test "$(grep -Fxc "PRIVATE-OBSERVATION-BEGIN run_id=$run_id input_sha256=$input_digest" "$log")" -eq 1 || {
  echo 'Private observation requires exactly one matching begin marker' >&2
  exit 1
}
test "$(grep -Fxc "PRIVATE-OBSERVATION-COMPLETE run_id=$run_id input_sha256=$input_digest" "$log")" -eq 1 || {
  echo 'Private observation requires exactly one completion marker' >&2
  exit 1
}
test "$(grep -c '^PRIVATE-CASE-END ' "$log")" -eq 6 || {
  echo 'Private observation requires exactly six case-end markers' >&2
  exit 1
}
for name in memory-before memory-after cpu-before cpu-after thread-before thread-after; do
  prefix="PRIVATE-CASE-END name=$name run_id=$run_id input_sha256=$input_digest case_id=$run_id:$name "
  test "$(grep -F "$prefix" "$log" | grep -Ec '^PRIVATE-CASE-END .* samples=([2-9]|[1-9][0-9]+) survivors=0$')" -eq 1 || {
    echo "Private observation requires exactly one case-end marker: $name" >&2
    exit 1
  }
done
echo 'PRIVATE-RESULT-CHECK-SUCCESS'
