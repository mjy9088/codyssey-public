#!/usr/bin/env bash
set -euo pipefail
# These scenarios explicitly exercise the opt-in Tailnet workflow.
export CODYSSEY_TAILNET_SETUP=1 CODYSSEY_MACOS_SETUP=0
root=/src
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ref=0123456789abcdef0123456789abcdef01234567
fakebin="$tmp/bin"
mkdir -p "$fakebin"

cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
output=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output=$2; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
if [ "$url" = 'http://127.0.0.1:18081/health' ] && [ -n "${UPGRADE_CASE:-}" ]; then exit 0; fi
relative=${url#*/environment/codyssey-init/}
if [ "${FAIL_FILE:-}" = "$relative" ]; then
  printf 'touch "$INITIAL_EXECUTED"\n' >"$output"
  exit 22
fi
source_file="$REMOTE_SOURCE/$relative"
[ -f "$source_file" ] || exit 22
cp "$source_file" "$output"
EOF
cat >"$fakebin/docker" <<'EOF'
#!/bin/sh
case "$*" in
  info|'compose build tailscale tunnel-ui'|'compose pull gost') exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat >"$fakebin/mise" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/zsh" <<'EOF'
#!/bin/sh
printf 'zsh %s\n' "$*" >>"$REMOTE_LOG"
EOF
chmod 0755 "$fakebin"/*

if (( $# == 1 )); then
  # Same public entry point and feature inputs for both releases. Only the
  # download transport is redirected to read-only release files.
  legacy=$1/environment/codyssey-init
  transport="$tmp/transport"
  stage="$tmp/stage"
  home="$tmp/home"
  mkdir -p "$transport" "$stage" "$home"
  cp "$fakebin/curl" "$transport/curl"
  cp "$fakebin/mise" "$transport/mise"
  cat >"$transport/docker" <<'EOF'
#!/bin/sh
case "$*" in
  'container ls --all '*)
    case ${UPGRADE_CASE:-} in
      legacy) printf 'tailnet-forward-gost\ntailnet-forward-ui\n' ;;
      unavailable) exit 1 ;;
    esac ;;
  info|'compose build tailscale tunnel-ui'|'compose pull gost') exit 0 ;;
  'compose up -d --no-build')
    printf 'startup\n' >>"$UPGRADE_LOG"
    diff -qr "$UPGRADE_EXPECTED" "$PWD" || exit 91
    if [ "${UPGRADE_CASE:-}" = concurrent ]; then
      : >"$UPGRADE_EVENTS/activation-ready"
      timeout 20 sh -c 'read -r _ <"$1"' sh "$UPGRADE_EVENTS/activation-gate"
    fi ;;
  'compose ps --status running --services') printf 'tailscale\ngost\ntunnel-ui\n' ;;
  'compose exec -T tailscale tailscale status --json') printf '{"BackendState":"Running"}\n' ;;
  *) exit 89 ;;
esac
EOF
  cat >"$transport/install" <<'EOF'
#!/bin/sh
case ${UPGRADE_CASE:-}:$3 in
  preparation:*/sdk/setup.mts) exit 72 ;;
  late-conflict:*/sdk/setup.mts) printf '\n# edited during staging\n' >>"$CODYSSEY_INIT_DIR/sdk/setup.mts" ;;
  concurrent:*/sdk/setup.mts)
    : >"$UPGRADE_EVENTS/staging-ready"
    timeout 20 sh -c 'read -r _ <"$1"' sh "$UPGRADE_EVENTS/staging-gate" || exit 73 ;;
esac
exec /usr/bin/install "$@"
EOF
  cat >"$transport/mv" <<'EOF'
#!/bin/sh
if [ "${UPGRADE_CASE:-}" = interruption ] && [ "$3" = "$CODYSSEY_INIT_DIR/docker-compose.yml" ]; then
  kill -TERM "$PPID"
  exit 143
fi
exec /bin/mv "$@"
EOF
  chmod 0755 "$transport/docker" "$transport/install" "$transport/mv"
  events="$tmp/events"
  mkdir "$events"
  mkfifo "$events/staging-gate" "$events/activation-gate"
  started="$tmp/activation.log"
  : >"$started"
  run_blocked_upgrade() {
    local test_case=$1 destination=$2 message=$3
    if run_release "$root" "$destination" CODYSSEY_TAILNET_SETUP=1 UPGRADE_CASE="$test_case" >"$tmp/blocked.log" 2>&1; then
      printf 'unsafe upgrade succeeded: %s\n' "$test_case" >&2
      exit 1
    fi
    if ! grep -Fq "$message" "$tmp/blocked.log"; then cat "$tmp/blocked.log" >&2; exit 1; fi
  }
  wait_for_event() {
    local event=$1 attempt
    for ((attempt=0; attempt<200; attempt++)); do
      [[ ! -e $events/$event ]] || return 0
      kill -0 "$upgrade_pid" 2>/dev/null || break
      sleep 0.05
    done
    cat "$tmp/overlap.log" >&2
    printf 'upgrade did not reach %s\n' "$event" >&2
    return 1
  }
  run_release() {
    local source=$1 destination=$2
    shift 2
    env -i HOME="$home" TMPDIR="$stage" PATH="$transport:/usr/bin:/bin" \
      CODYSSEY_INIT_DIR="$destination" REMOTE_SOURCE="$source" \
      CODYSSEY_TAILNET_SETUP=0 CODYSSEY_MACOS_SETUP=0 CODYSSEY_INSTALL_J=0 \
      CODYSSEY_OPEN_BROWSER=0 UPGRADE_LOG="$started" UPGRADE_EXPECTED="$fresh" UPGRADE_EVENTS="$events" \
      "$@" sh <"$legacy/../../init.sh"
  }

  fresh="$tmp/fresh"
  run_release "$root" "$fresh"
  cmp "$fresh/docker-compose.yml" "$root/docker-compose.yml"
  cmp "$fresh/tunnel-ui/index.html" "$root/tunnel-ui/index.html"
  [[ ! -e $fresh/.env ]]
  printf 'PASS: fresh download installs the tunnel UI\n'

  old="$tmp/installed with spaces"
  run_release "$legacy" "$old"
  cmp "$old/docker-compose.yml" "$legacy/docker-compose.yml"
  [[ ! -e $old/tunnel-ui ]]
  install -m 0600 /dev/null "$old/.env"
  printf 'TS_AUTHKEY=synthetic-saved-value\n' >"$old/.env"
  cat >"$old/gost/gost.yaml" <<'EOF'
# Existing configuration owned by the installer user.
services:
  - name: previous-preview
    addr: 127.0.0.1:19090
    handler: {type: tcp}
    listener: {type: tcp}
    forwarder: {nodes: [{name: preview, addr: '127.0.0.1:3000'}]}
    futureField: {keep: 'exactly as written'}
api: {addr: '127.0.0.1:18080'}
EOF
  cp -p "$old/.env" "$fresh/.env"
  cp -p "$old/gost/gost.yaml" "$fresh/gost/gost.yaml"
  # Include the empty advisory lock inode in snapshots, not as a managed file.
  : >"$old/.codyssey-installer.lock"
  snapshot="$tmp/old-before"
  cp -a "$old" "$snapshot"
  run_blocked_upgrade legacy "$old" 'run docker compose down with the old Compose file'
  diff -qr "$snapshot" "$old"
  cmp "$legacy/docker-compose.yml" "$old/docker-compose.yml"
  run_blocked_upgrade unavailable "$old" 'Cannot check for legacy GOST containers'
  diff -qr "$snapshot" "$old"
  [[ ! -s $started ]]
  printf 'PASS: legacy stack blocks publication; the complete prior install and teardown Compose remain intact\n'

  run_blocked_upgrade preparation "$old" 'could not stage'
  diff -qr "$snapshot" "$old"
  conflict="$tmp/late-conflict"
  cp -a "$old" "$conflict"
  run_blocked_upgrade late-conflict "$conflict" "refusing to overwrite modified $conflict/sdk/setup.mts"
  expected="$tmp/conflict-expected"
  cp -a "$snapshot" "$expected"
  printf '\n# edited during staging\n' >>"$expected/sdk/setup.mts"
  diff -qr "$expected" "$conflict"
  [[ ! -s $started ]]
  printf 'PASS: failed preparation and a conflict introduced during staging do not publish earlier files\n'

  interrupted="$tmp/interrupted"
  cp -a "$old" "$interrupted"
  if run_release "$root" "$interrupted" UPGRADE_CASE=interruption CODYSSEY_TAILNET_SETUP=1; then
    printf 'interrupted publication unexpectedly succeeded\n' >&2; exit 1
  fi
  cmp "$interrupted/docker-compose.yml" "$legacy/docker-compose.yml"
  cmp "$interrupted/next-script.zsh" "$root/next-script.zsh"
  if zsh "$interrupted/next-script.zsh" --prepared >"$tmp/blocked.log" 2>&1; then
    printf 'interrupted install activated\n' >&2; exit 1
  fi
  grep -Fq 'An installer update is incomplete' "$tmp/blocked.log"
  [[ ! -s $started ]]
  run_release "$root" "$interrupted"
  diff -qr "$fresh" "$interrupted"
  printf 'PASS: interrupted publication cannot activate and is repaired by a normal retry\n'

  overlap="$tmp/overlap"
  cp -a "$old" "$overlap"
  run_release "$root" "$overlap" UPGRADE_CASE=concurrent CODYSSEY_TAILNET_SETUP=1 TS_AUTHKEY='' >"$tmp/overlap.log" 2>&1 &
  upgrade_pid=$!
  wait_for_event staging-ready
  run_blocked_upgrade '' "$overlap" 'another installer is using'
  [[ ! -s $started ]]
  cmp "$overlap/docker-compose.yml" "$legacy/docker-compose.yml"
  printf '\n' >"$events/staging-gate"
  wait_for_event activation-ready
  run_blocked_upgrade '' "$overlap" 'another installer is using'
  printf '\n' >"$events/activation-gate"
  if ! wait "$upgrade_pid"; then cat "$tmp/overlap.log" >&2; exit 1; fi
  [[ $(cat "$started") == startup ]]
  diff -qr "$fresh" "$overlap"
  printf 'PASS: concurrent runs cannot publish or activate during staging or activation\n'


  for file in docker-compose.yml sdk/setup.mts; do
    custom="$tmp/custom"
    snapshot="$tmp/custom-before"
    cp -a "$old" "$custom"
    printf '\n# intentionally customized\n' >>"$custom/$file"
    cp -a "$custom" "$snapshot"
    if run_release "$root" "$custom" >"$tmp/conflict.log" 2>&1; then
      printf 'customized %s was overwritten\n' "$file" >&2
      exit 1
    fi
    if ! grep -Fq "refusing to overwrite modified $custom/$file" "$tmp/conflict.log" ||
        ! grep -Fq 'Back up and review this path' "$tmp/conflict.log"; then
      cat "$tmp/conflict.log" >&2
      exit 1
    fi
    diff -qr "$snapshot" "$custom"
    rm -rf "$custom" "$snapshot"
  done
  printf 'PASS: customized early and late files refused before publishing anything\n'

  run_release "$root" "$old"
  diff -qr "$fresh" "$old"
  [[ $(stat -c %a "$old/.env") == 600 ]]
  printf 'PASS: byte-exact prior install upgraded in place; credentials and tunnels preserved\n'

  before=$(stat -c '%i:%Y' "$old/docker-compose.yml")
  run_release "$root" "$old"
  diff -qr "$fresh" "$old"
  [[ $(stat -c '%i:%Y' "$old/docker-compose.yml") == "$before" ]]
  [[ -z $(find "$stage" -mindepth 1 -print -quit) ]]
  printf 'PASS: repeated upgrade leaves installed files in place and cleans staging\n'
  exit 0
fi

# A failed initial download may have written executable shell text. The documented
# download-then-run contract must not execute that incomplete file.
download_then_run() (
  installer=$(mktemp) || exit 1
  trap 'rm -f "$installer"' EXIT
  curl --fail --location --silent --show-error \
    "https://example.invalid/repository/$ref/environment/codyssey-init/init.sh" \
    -o "$installer" && bash "$installer"
)
if PATH="$fakebin:/usr/bin:/bin" FAIL_FILE=init.sh REMOTE_SOURCE=$root \
  INITIAL_EXECUTED="$tmp/initial-executed" download_then_run; then
  printf 'failed initial download unexpectedly succeeded\n' >&2
  exit 1
fi
[[ ! -e "$tmp/initial-executed" ]] || { printf 'partial installer ran\n' >&2; exit 1; }

run_pipe() {
  HOME=$1 CODYSSEY_INIT_DIR=$2 \
    PATH="$fakebin:/usr/bin:/bin" REMOTE_SOURCE=$root \
    REMOTE_LOG="$tmp/remote.log" TMPDIR=$3 bash <"$root/init.sh"
}

home="$tmp/home"
target="$tmp/install"
stage="$tmp/stage"
mkdir -p "$home" "$stage" "$target/gost"
printf 'TS_AUTHKEY=preserved\n' >"$target/.env"
printf 'services: [preserved]\n' >"$target/gost/gost.yaml"
run_pipe "$home" "$target" "$stage"
for file in init.sh verify-macos-setup.py next-script.zsh lib/auth.sh lib/preparation.sh \
  lib/readiness.zsh scripts/prepare-startup.sh Dockerfile; do
  [[ -f "$target/$file" ]] || { printf 'missing remote file: %s\n' "$file" >&2; exit 1; }
done
grep -qx 'TS_AUTHKEY=preserved' "$target/.env"
grep -qx 'services: \[preserved\]' "$target/gost/gost.yaml"
run_pipe "$home" "$target" "$stage"

printf 'locally modified\n' >"$target/tailnet.sh"
rm "$target/Dockerfile"
if run_pipe "$home" "$target" "$stage" >/dev/null 2>&1; then
  printf 'modified installer was overwritten\n' >&2
  exit 1
fi
[[ ! -e "$target/Dockerfile" ]] || { printf 'preflight copied before conflict\n' >&2; exit 1; }

failed="$tmp/failed"
failed_stage="$tmp/failed-stage"
mkdir -p "$failed_stage"
if FAIL_FILE=mise.toml run_pipe "$home" "$failed" "$failed_stage" >/dev/null 2>&1; then
  printf 'failed download unexpectedly succeeded\n' >&2
  exit 1
fi
[[ ! -e "$failed" ]] || { printf 'failed download copied target files\n' >&2; exit 1; }
[[ -z $(find "$failed_stage" -mindepth 1 -print -quit) ]] || { printf 'staging was not cleaned\n' >&2; exit 1; }
