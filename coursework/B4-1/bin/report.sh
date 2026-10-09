#!/usr/bin/env bash
set -euo pipefail

log_file=${1:-${AGENT_LOG_FILE:-/var/log/agent-app/monitor.log}}
if [[ ! -r "$log_file" ]]; then
  printf '[ERROR] cannot read monitor log: %s\n' "$log_file" >&2
  exit 1
fi
awk '
  match($0, /CPU:([0-9.]+)% MEM:([0-9.]+)% DISK_USED:([0-9.]+)%/, values) {
    cpu=values[1]+0; mem=values[2]+0; disk=values[3]+0
    if (count == 0 || cpu < cpu_min) cpu_min=cpu
    if (count == 0 || mem < mem_min) mem_min=mem
    if (count == 0 || disk < disk_min) disk_min=disk
    if (count == 0 || cpu > cpu_max) cpu_max=cpu
    if (count == 0 || mem > mem_max) mem_max=mem
    if (count == 0 || disk > disk_max) disk_max=disk
    cpu_sum+=cpu; mem_sum+=mem; disk_sum+=disk; count++
  }
  END {
    if (count == 0) { print "[ERROR] no valid samples" > "/dev/stderr"; exit 1 }
    print "====== STATISTICS REPORT ======"
    printf "CPU avg=%.1f min=%.1f max=%.1f\n", cpu_sum/count, cpu_min, cpu_max
    printf "MEM avg=%.1f min=%.1f max=%.1f\n", mem_sum/count, mem_min, mem_max
    printf "DISK avg=%.1f min=%.1f max=%.1f\n", disk_sum/count, disk_min, disk_max
    printf "Samples=%d\n", count
  }
' "$log_file"
