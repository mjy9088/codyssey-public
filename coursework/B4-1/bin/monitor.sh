#!/usr/bin/env bash
set -euo pipefail

process_pattern=${AGENT_PROCESS_PATTERN:-agent-app}
port=${AGENT_PORT:-15034}
log_file=${AGENT_LOG_FILE:-/var/log/agent-app/monitor.log}
disk_path=${MONITOR_DISK_PATH:-/}
cpu_limit=${CPU_WARNING_PERCENT:-20}
mem_limit=${MEM_WARNING_PERCENT:-10}
disk_limit=${DISK_WARNING_PERCENT:-80}
max_bytes=${MONITOR_MAX_BYTES:-10485760}

pid=$(pgrep -f -- "$process_pattern" | head -n 1 || true)
if [[ -z "$pid" ]]; then
  printf '[ERROR] process %s is not running\n' "$process_pattern" >&2
  exit 1
fi
if ! ss -ltnH "sport = :$port" | grep -q .; then
  printf '[ERROR] TCP port %s is not listening\n' "$port" >&2
  exit 1
fi

firewall_state=inactive
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall_state=$(firewall-cmd --state 2>/dev/null || true)
fi
if [[ "$firewall_state" != running ]] && pgrep -f '[f]irewalld' >/dev/null 2>&1; then
  firewall_state=running
fi
if [[ "$firewall_state" != running ]]; then
  printf '[WARNING] firewall is not active\n'
fi

read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total_before=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle_before=$((idle + iowait))
sleep 1
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total_after=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle_after=$((idle + iowait))
total_delta=$((total_after - total_before))
idle_delta=$((idle_after - idle_before))
cpu=$(awk -v total="$total_delta" -v idle="$idle_delta" 'BEGIN { if (total == 0) print "0.0"; else printf "%.1f", 100 * (total-idle) / total }')
mem=$(awk '/MemTotal:/ { total=$2 } /MemAvailable:/ { available=$2 } END { printf "%.1f", 100 * (total-available) / total }' /proc/meminfo)
disk=$(df -P "$disk_path" | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')

mkdir -p "$(dirname "$log_file")"
if [[ -f "$log_file" ]] && (( $(stat -c %s "$log_file") >= max_bytes )); then
  rm -f "$log_file.10"
  for ((index=9; index>=1; index--)); do
    [[ -f "$log_file.$index" ]] && mv "$log_file.$index" "$log_file.$((index + 1))"
  done
  mv "$log_file" "$log_file.1"
fi
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n' "$timestamp" "$pid" "$cpu" "$mem" "$disk" | tee -a "$log_file"

if awk -v value="$cpu" -v limit="$cpu_limit" 'BEGIN { exit !(value > limit) }'; then
  printf '[WARNING] CPU threshold exceeded (%s%% > %s%%)\n' "$cpu" "$cpu_limit"
fi
if awk -v value="$mem" -v limit="$mem_limit" 'BEGIN { exit !(value > limit) }'; then
  printf '[WARNING] MEM threshold exceeded (%s%% > %s%%)\n' "$mem" "$mem_limit"
fi
if awk -v value="$disk" -v limit="$disk_limit" 'BEGIN { exit !(value > limit) }'; then
  printf '[WARNING] DISK threshold exceeded (%s%% > %s%%)\n' "$disk" "$disk_limit"
fi
