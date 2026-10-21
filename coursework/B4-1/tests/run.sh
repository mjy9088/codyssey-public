#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d)
app_pid=
cleanup() {
  [[ -n "$app_pid" ]] && kill "$app_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

bash "$root/tests/private-contract.sh"
if [[ -f $root/scripts/verify-private.sh ]]; then
  bash "$root/tests/verify-routing.sh"
  bash "$root/tests/private-wrapper-guards.sh"
fi
sh "$root/tests/verify-lifecycle.sh"

AGENT_PORT=15034 "$root/tests/synthetic-app.sh" >"$tmp/app.log" 2>&1 &
app_pid=$!
for _ in $(seq 1 20); do
  ss -ltnH 'sport = :15034' | grep -q . && break
  sleep 0.1
done
AGENT_PROCESS_PATTERN=agent-app-synthetic AGENT_PORT=15034 AGENT_LOG_FILE="$tmp/monitor.log" \
  CPU_WARNING_PERCENT=101 MEM_WARNING_PERCENT=101 DISK_WARNING_PERCENT=101 \
  "$root/bin/monitor.sh" >"$tmp/monitor.out"
grep -q 'PID:' "$tmp/monitor.log"
grep -q 'firewall is not active' "$tmp/monitor.out"
printf '[2026-01-01 00:00:00] PID:1 CPU:10.0%% MEM:20.0%% DISK_USED:30%%\n' >>"$tmp/monitor.log"
report=$($root/bin/report.sh "$tmp/monitor.log")
printf '%s\n' "$report" | grep -q '^Samples=2$'
if AGENT_PROCESS_PATTERN=definitely-missing AGENT_PORT=15034 AGENT_LOG_FILE="$tmp/missing.log" \
  "$root/bin/monitor.sh" >/dev/null 2>&1; then
  printf 'missing process unexpectedly passed\n' >&2
  exit 1
fi
if AGENT_PROCESS_PATTERN=agent-app-synthetic AGENT_PORT=15035 AGENT_LOG_FILE="$tmp/missing-port.log" \
  "$root/bin/monitor.sh" >/dev/null 2>&1; then
  printf 'missing port unexpectedly passed\n' >&2
  exit 1
fi

AGENT_PROCESS_PATTERN=agent-app-synthetic AGENT_PORT=15034 AGENT_LOG_FILE="$tmp/warnings.log" \
  CPU_WARNING_PERCENT=-1 MEM_WARNING_PERCENT=-1 DISK_WARNING_PERCENT=-1 \
  "$root/bin/monitor.sh" >"$tmp/warnings.out"
grep -q 'CPU threshold exceeded' "$tmp/warnings.out"
grep -q 'MEM threshold exceeded' "$tmp/warnings.out"
grep -q 'DISK threshold exceeded' "$tmp/warnings.out"
grep -q 'PID:' "$tmp/warnings.log"

for index in $(seq 1 10); do
  printf 'rotation-%s\n' "$index" >"$tmp/rotation.log.$index"
done
truncate -s 10485760 "$tmp/rotation.log"
AGENT_PROCESS_PATTERN=agent-app-synthetic AGENT_PORT=15034 AGENT_LOG_FILE="$tmp/rotation.log" \
  CPU_WARNING_PERCENT=101 MEM_WARNING_PERCENT=101 DISK_WARNING_PERCENT=101 \
  "$root/bin/monitor.sh" >/dev/null
test "$(stat -c %s "$tmp/rotation.log.1")" -eq 10485760
grep -q '^rotation-9$' "$tmp/rotation.log.10"
test ! -e "$tmp/rotation.log.11"
grep -q 'PID:' "$tmp/rotation.log"

printf 'not a monitor sample\n' >"$tmp/malformed.log"
if "$root/bin/report.sh" "$tmp/malformed.log" >/dev/null 2>&1; then
  printf 'malformed report unexpectedly passed\n' >&2
  exit 1
fi
printf '[2026-01-01 00:00:00] PID:1 CPU:1.0%% MEM:2.0%% DISK_USED:3%%\nmalformed\n' \
  >"$tmp/mixed.log"
if "$root/bin/report.sh" "$tmp/mixed.log" >/dev/null 2>&1; then
  printf 'mixed report unexpectedly passed\n' >&2
  exit 1
fi
printf 'SYNTHETIC-TEST-SUCCESS\n'
