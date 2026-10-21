#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
fixture=$tmp/repo/coursework/B4-1
mkdir -p "$fixture/scripts" "$tmp/repo/.git" "$tmp/repo/.local/B4-1" "$tmp/bin"
cp "$root/scripts/verify.sh" "$fixture/scripts/verify.sh"
cat >"$fixture/scripts/verify-private.sh" <<'EOF'
#!/bin/sh
printf '%s\n%s\n' "$1" "$2" >>"$ROUTING_LOG"
exit "${PRIVATE_STATUS:-0}"
EOF
cat >"$tmp/bin/docker" <<'EOF'
#!/bin/sh
printf 'docker:%s\n' "$*" >>"$DOCKER_LOG"
exit 0
EOF
chmod +x "$tmp/bin/docker"
: >"$tmp/routing.log"
: >"$tmp/docker.log"
: >"$tmp/repo/.local/B4-1/agent-app.zip"
ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" all >/dev/null
mapfile -t routed <"$tmp/routing.log"
[[ ${#routed[@]} -eq 2 ]]
[[ ${routed[0]} == "$tmp/repo/.local/B4-1/agent-app.zip" ]]
[[ ${routed[1]} == "$tmp/repo/.local/evidence/B4-1" ]]
[[ ! -s $tmp/docker.log ]]
set +e
PRIVATE_STATUS=23 ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" docker >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 23 ]]
[[ ! -s $tmp/docker.log ]]
ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" synthetic-docker >/dev/null
grep -q '^docker:' "$tmp/docker.log"
rm "$tmp/repo/.local/B4-1/agent-app.zip"
: >"$tmp/docker.log"
ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" docker >/dev/null
grep -q '^docker:' "$tmp/docker.log"
printf 'VERIFY-ROUTING-SUCCESS (provided once, failure propagated, explicit synthetic preserved)\n'
