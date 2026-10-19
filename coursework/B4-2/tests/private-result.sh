#!/bin/sh
set -eu
test "$#" -eq 1
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
out=$1
log="$out/private-result.log"
run_id=run.TEST123
input_digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

echo "PRIVATE-OBSERVATION-BEGIN run_id=$run_id input_sha256=$input_digest" >"$log"
for name in memory-before memory-after cpu-before cpu-after thread-before thread-after; do
  echo "PRIVATE-CASE-END name=$name run_id=$run_id input_sha256=$input_digest case_id=$run_id:$name status=0 origin=child-exit termination=test kernel_oom_evidence=no samples=2 survivors=0" >>"$log"
done
echo "PRIVATE-OBSERVATION-COMPLETE run_id=$run_id input_sha256=$input_digest" >>"$log"
sh "$root/bin/check-private-result.sh" "$log" 0 "$run_id" "$input_digest" >/dev/null

if sh "$root/bin/check-private-result.sh" "$log" 124 "$run_id" "$input_digest" >/dev/null 2>&1; then
  echo 'private result checker accepted timeout status' >&2
  exit 1
fi
if sh "$root/bin/check-private-result.sh" "$log" 0 run.STALE1 "$input_digest" >/dev/null 2>&1; then
  echo 'private result checker accepted a stale run identity' >&2
  exit 1
fi
stale_digest=abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789
if sh "$root/bin/check-private-result.sh" "$log" 0 "$run_id" "$stale_digest" >/dev/null 2>&1; then
  echo 'private result checker accepted a different input digest' >&2
  exit 1
fi
sed -i "s/case_id=$run_id:cpu-before/case_id=$run_id:memory-before/" "$log"
if sh "$root/bin/check-private-result.sh" "$log" 0 "$run_id" "$input_digest" >/dev/null 2>&1; then
  echo 'private result checker accepted a stale case identity' >&2
  exit 1
fi
sed -i "s/case_id=$run_id:memory-before status=0 origin=child-exit termination=test/case_id=$run_id:cpu-before status=0 origin=child-exit termination=test/2" "$log"
echo 'PRIVATE-OBSERVATION-BLOCKED: synthetic regression fixture' >>"$log"
if sh "$root/bin/check-private-result.sh" "$log" 0 "$run_id" "$input_digest" >/dev/null 2>&1; then
  echo 'private result checker accepted blocked marker' >&2
  exit 1
fi
sed -i '$d' "$log"
sed -i '/^PRIVATE-CASE-END name=thread-after /d' "$log"
if sh "$root/bin/check-private-result.sh" "$log" 0 "$run_id" "$input_digest" >/dev/null 2>&1; then
  echo 'private result checker accepted missing case marker' >&2
  exit 1
fi
echo 'PRIVATE-RESULT-REGRESSION-CHECK=run-identity,input-digest,case-freshness'
