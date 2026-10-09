#!/bin/sh
set -eu
test "$#" -ge 2 && test "$#" -le 4 || {
  echo "Usage: $0 PID LOG [COUNT [INTERVAL]]" >&2
  exit 2
}
pid=$1
log=$2
count=${3:-10}
interval=${4:-0.25}
case "$pid:$count" in *[!0-9:]*|:*|*:) echo 'PID and COUNT must be positive integers' >&2; exit 2 ;; esac
test "$pid" -gt 0 && test "$count" -gt 0 || exit 2
mkdir -p "$(dirname "$log")"
read_starttime() {
  stat_line=$(cat "/proc/$1/stat" 2>/dev/null || true)
  test -n "$stat_line" || return 1
  stat_fields=${stat_line##*) }
  printf '%s\n' "$stat_fields" | awk 'NF >= 20 && $20 ~ /^[0-9]+$/ { print $20 }'
}
start=$(read_starttime "$pid" || true)
test -n "$start" || { echo "process not found: $pid" >&2; exit 1; }
i=0
while test "$i" -lt "$count"; do
  test -r "/proc/$pid/stat" || break
  current=$(read_starttime "$pid" || true)
  test "$current" = "$start" || break
  values=$(ps -o %cpu=,rss=,stat=,nlwp= -p "$pid" | awk 'NF == 4 {print $1, $2, $3, $4}')
  test -n "$values" || break
  set -- $values
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  elapsed=$(awk '{printf "%.2f", $1}' /proc/uptime)
  printf 'timestamp=%s elapsed=%s pid=%s cpu_pct=%s rss_kb=%s state=%s threads=%s\n' \
    "$timestamp" "$elapsed" "$pid" "$1" "$2" "$3" "$4" | tee -a "$log"
  i=$((i + 1))
  sleep "$interval"
done
