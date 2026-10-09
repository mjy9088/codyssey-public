#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
output_base=${LAB_OUTPUT_DIR:-/tmp/b4-2-artifacts}
mkdir -p "$output_base"
out=$(mktemp -d "$output_base/run.XXXXXX")
app_pid=
deadlock_pid=
parse_pid=
cleanup() {
  test -n "$app_pid" && kill "$app_pid" 2>/dev/null || true
  test -n "$deadlock_pid" && kill "$deadlock_pid" 2>/dev/null || true
  test -n "$parse_pid" && kill "$parse_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
echo "LAB-OUTPUT-DIR=$out"

metric_value() {
  key=$1
  awk -v key="$key" 'NR == 1 { for (i=1; i<=NF; i++) if ($i ~ ("^" key "=")) { sub("^[^=]*=", "", $i); print $i; exit } }'
}

metric_max() {
  key=$1
  awk -v key="$key" '
    { for (i=1; i<=NF; i++) if ($i ~ ("^" key "=")) { split($i, value, "="); if (value[2]+0 > maximum) maximum=value[2]+0 } }
    END { print maximum+0 }
  '
}

private_result_fixture="$out/private-result.log"
for name in memory-before memory-after cpu-before cpu-after thread-before thread-after; do
  echo "PRIVATE-CASE-END name=$name status=0 origin=child-exit termination=test kernel_oom_evidence=no samples=2 survivors=0" >>"$private_result_fixture"
done
echo 'PRIVATE-OBSERVATION-COMPLETE' >>"$private_result_fixture"
"$root/bin/check-private-result.sh" "$private_result_fixture" 0 >/dev/null
if "$root/bin/check-private-result.sh" "$private_result_fixture" 124 >/dev/null 2>&1; then
  echo 'private result checker accepted timeout status' >&2
  exit 1
fi
echo 'PRIVATE-OBSERVATION-BLOCKED: synthetic regression fixture' >>"$private_result_fixture"
if "$root/bin/check-private-result.sh" "$private_result_fixture" 0 >/dev/null 2>&1; then
  echo 'private result checker accepted blocked marker' >&2
  exit 1
fi
sed -i '$d' "$private_result_fixture"
sed -i '/^PRIVATE-CASE-END name=thread-after /d' "$private_result_fixture"
if "$root/bin/check-private-result.sh" "$private_result_fixture" 0 >/dev/null 2>&1; then
  echo 'private result checker accepted missing case marker' >&2
  exit 1
fi
echo 'PRIVATE-RESULT-REGRESSION-CHECK=yes'

native_marker="$out/native-124.marker"
set +e
"$root/bin/supervise.sh" "$native_marker" 2 1 -- sh -c 'exit 124'
native_status=$?
set -e
test "$native_status" -eq 124
test ! -e "$native_marker"
deadline_marker="$out/deadline.marker"
set +e
"$root/bin/supervise.sh" "$deadline_marker" 0.2 0.2 -- sh -c 'trap "" TERM; while :; do :; done'
deadline_status=$?
set -e
test "$deadline_status" -eq 137
grep -q '^SUPERVISOR-DEADLINE ' "$deadline_marker"
echo 'SUPERVISOR-REGRESSION-CHECK native-124=child-exit term-ignoring=deadline-kill'

sh -c 'printf "odd ) name\n" >/proc/self/comm; while :; do :; done' &
parse_pid=$!
"$root/bin/monitor.sh" "$parse_pid" "$out/stat-parser.monitor.log" 1 0 >/dev/null
grep -q "pid=$parse_pid " "$out/stat-parser.monitor.log"
kill "$parse_pid"
wait "$parse_pid" 2>/dev/null || true
parse_pid=
echo 'PROC-STAT-PARSER-CHECK comm-with-space-and-closing-paren=yes'

run_monitored() {
  name=$1; shift
  set +e
  "$@" >"$out/$name.app.log" 2>&1 &
  app_pid=$!
  set -e
  "$root/bin/monitor.sh" "$app_pid" "$out/$name.monitor.log" 60 0.10 >/dev/null 2>&1 &
  monitor_pid=$!
  set +e
  wait "$app_pid"
  status=$?
  app_pid=
  wait "$monitor_pid"
  set -e
  printf '%s\n' "$status" >"$out/$name.status"
}

run_monitored memory-before env MEMORY_LIMIT=50 "$root/bin/resource-fixture" memory
run_monitored memory-after env MEMORY_LIMIT=80 "$root/bin/resource-fixture" memory
echo "MEMORY-RUN-STATUS before=$(cat "$out/memory-before.status") after=$(cat "$out/memory-after.status")"
grep -q 'SELF-TERMINATED: application MemoryGuard policy (not kernel OOM)' "$out/memory-before.app.log" || {
  cat "$out/memory-before.app.log" >&2
  echo 'memory-before policy marker missing' >&2
  exit 1
}
grep -q 'Memory limit exceeded' "$out/memory-before.app.log"
grep -q 'SELF-TERMINATED: application MemoryGuard policy (not kernel OOM)' "$out/memory-after.app.log" || {
  cat "$out/memory-after.app.log" >&2
  echo 'memory-after policy marker missing' >&2
  exit 1
}
grep -q 'Memory limit exceeded' "$out/memory-after.app.log"
test "$(cat "$out/memory-before.status")" -eq 42
test "$(cat "$out/memory-after.status")" -eq 42
mem_before_first=$(metric_value rss_kb <"$out/memory-before.monitor.log")
mem_before_max=$(metric_max rss_kb <"$out/memory-before.monitor.log")
mem_after_first=$(metric_value rss_kb <"$out/memory-after.monitor.log")
mem_after_max=$(metric_max rss_kb <"$out/memory-after.monitor.log")
mem_after_samples=$(wc -l <"$out/memory-after.monitor.log")
mem_before_samples=$(wc -l <"$out/memory-before.monitor.log")
echo "MEMORY-METRICS before=$mem_before_first..$mem_before_max after=$mem_after_first..$mem_after_max samples-before=$mem_before_samples samples-after=$mem_after_samples"
test "$mem_before_max" -gt "$mem_before_first"
test "$mem_after_max" -gt "$mem_after_first"
test "$mem_after_samples" -gt "$mem_before_samples"
echo "MEMORY-CHECK before-rss-kb=$mem_before_first..$mem_before_max after-rss-kb=$mem_after_first..$mem_after_max samples-before=$mem_before_samples samples-after=$mem_after_samples target-policy-exit=yes"

run_monitored cpu-before env CPU_MAX_OCCUPY=25 "$root/bin/resource-fixture" cpu
run_monitored cpu-after env CPU_MAX_OCCUPY=100 "$root/bin/resource-fixture" cpu
grep -q 'WATCHDOG SIGTERM observed; application stopped by policy' "$out/cpu-before.app.log"
grep -q 'WATCHDOG threshold exceeded' "$out/cpu-before.app.log"
grep -q 'CPU_CONTROL_COMPLETED' "$out/cpu-after.app.log"
test "$(cat "$out/cpu-before.status")" -eq 43
test "$(cat "$out/cpu-after.status")" -eq 0
cpu_peak=$(awk '{ for (i=1; i<=NF; i++) if ($i ~ /^cpu_pct=/) { split($i, value, "="); if (value[2]+0 > max) max=value[2]+0 } } END {print max+0}' "$out/cpu-before.monitor.log")
awk -v peak="$cpu_peak" 'BEGIN {exit !(peak >= 50)}'
echo "CPU-CHECK peak_pct=$cpu_peak threshold-before=25 watchdog-exit=yes threshold-after=100 control-completed=yes"

env MULTI_THREAD_ENABLE=true "$root/bin/resource-fixture" deadlock >"$out/deadlock-before.app.log" 2>&1 &
deadlock_pid=$!
sleep 0.5
kill -0 "$deadlock_pid"
deadlock_log_size_before=$(wc -c <"$out/deadlock-before.app.log")
ps -L -o pid=,tid=,stat=,pcpu=,rss=,comm= -p "$deadlock_pid" >"$out/deadlock-before.threads-first.log"
"$root/bin/monitor.sh" "$deadlock_pid" "$out/deadlock-before.monitor.log" 8 0.15 >/dev/null
kill -0 "$deadlock_pid"
ps -L -o pid=,tid=,stat=,pcpu=,rss=,comm= -p "$deadlock_pid" >"$out/deadlock-before.threads-last.log"
deadlock_log_size_after=$(wc -c <"$out/deadlock-before.app.log")
grep -q 'Thread-A WAITING BLOCKED on peer lock' "$out/deadlock-before.app.log"
grep -q 'Thread-B WAITING BLOCKED on peer lock' "$out/deadlock-before.app.log"
test "$deadlock_log_size_before" -eq "$deadlock_log_size_after"
test "$(wc -l <"$out/deadlock-before.threads-first.log")" -ge 3
test "$(wc -l <"$out/deadlock-before.threads-last.log")" -ge 3
awk '$3 ~ /^S/ { sleeping++ } END { exit !(sleeping >= 3) }' "$out/deadlock-before.threads-first.log"
awk '$3 ~ /^S/ { sleeping++ } END { exit !(sleeping >= 3) }' "$out/deadlock-before.threads-last.log"
first_tids=$(awk '{print $2}' "$out/deadlock-before.threads-first.log" | sort -n | tr '\n' ' ')
last_tids=$(awk '{print $2}' "$out/deadlock-before.threads-last.log" | sort -n | tr '\n' ' ')
test "$first_tids" = "$last_tids"
awk '
  {
    rss=threads=-1
    for (i=1; i<=NF; i++) {
      if ($i ~ /^rss_kb=/) { split($i, value, "="); rss=value[2]+0 }
      if ($i ~ /^threads=/) { split($i, value, "="); threads=value[2]+0 }
    }
    if (rss < 0 || threads < 3) exit 1
    if (NR == 1 || rss < minimum) minimum=rss
    if (NR == 1 || rss > maximum) maximum=rss
  }
  END { if (NR != 8 || maximum-minimum > 1024) exit 1 }
' "$out/deadlock-before.monitor.log"
kill "$deadlock_pid"
wait "$deadlock_pid" 2>/dev/null || true
deadlock_pid=
env MULTI_THREAD_ENABLE=false "$root/bin/resource-fixture" deadlock >"$out/deadlock-after.app.log" 2>&1
grep -q 'SINGLE_THREAD_CONTROL_COMPLETED without circular wait' "$out/deadlock-after.app.log"
echo "DEADLOCK-CHECK pid-persisted=yes blocked-log-pairs=2 metrics-stable=yes thread-set-stable=yes log-stable=yes control-completed=yes"
echo 'SYNTHETIC-LAB-SUCCESS'
