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
printf 'SYNTHETIC-TEST-SUCCESS\n'
