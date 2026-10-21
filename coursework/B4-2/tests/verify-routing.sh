#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
fixture=$tmp/repo/coursework/B4-2
mkdir -p "$fixture/scripts" "$tmp/repo/.git" "$tmp/repo/.local/B4-2" "$tmp/bin"
cp "$root/scripts/verify.sh" "$fixture/scripts/verify.sh"
cat >"$fixture/scripts/observe-private.sh" <<'EOF'
#!/bin/sh
printf '%s\n%s\n' "$1" "$2" >>"$ROUTING_LOG"
exit "${PRIVATE_STATUS:-0}"
EOF
cat >"$tmp/bin/docker" <<'EOF'
#!/bin/sh
printf 'docker:%s\n' "$*" >>"$DOCKER_LOG"
case "$*" in
  *' run '*)
    printf '%s\n' 'MEMORY-CHECK synthetic' 'CPU-CHECK synthetic' 'DEADLOCK-CHECK synthetic' 'SYNTHETIC-LAB-SUCCESS'
    ;;
esac
exit 0
EOF
chmod +x "$tmp/bin/docker"
: >"$tmp/routing.log"
: >"$tmp/docker.log"
: >"$tmp/repo/.local/B4-2/agent-app-leak.zip"
ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" all >/dev/null
test "$(wc -l <"$tmp/routing.log")" -eq 2
test "$(sed -n '1p' "$tmp/routing.log")" = "$tmp/repo/.local/B4-2/agent-app-leak.zip"
test "$(sed -n '2p' "$tmp/routing.log")" = "$tmp/repo/.local/evidence/B4-2"
test ! -s "$tmp/docker.log"
set +e
PRIVATE_STATUS=23 ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" docker >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 23
test ! -s "$tmp/docker.log"
ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" synthetic-docker >/dev/null
grep -q '^docker:' "$tmp/docker.log"
rm "$tmp/repo/.local/B4-2/agent-app-leak.zip"
: >"$tmp/docker.log"
ROUTING_LOG=$tmp/routing.log DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify.sh" docker >/dev/null
grep -q '^docker:' "$tmp/docker.log"
printf 'VERIFY-ROUTING-SUCCESS (provided once, failure propagated, explicit synthetic preserved)\n'
