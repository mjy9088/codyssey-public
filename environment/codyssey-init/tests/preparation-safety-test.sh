#!/usr/bin/env bash
set -euo pipefail

root=${TEST_ROOT:-/src}
tmp=$(mktemp -d)
test_processes=
cleanup_test() {
  local process
  for process in $test_processes; do
    kill -KILL "$process" 2>/dev/null || true
    wait "$process" 2>/dev/null || true
  done
  rm -rf "$tmp"
}
trap cleanup_test EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
work="$tmp/work"
cp -R "$root/." "$work"
fakebin="$tmp/bin"
runtime="$tmp/runtime"
mkdir -p "$fakebin" "$runtime"

cat >"$fakebin/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf 'Linux\n' ;;
  -m) printf 'x86_64\n' ;;
esac
EOF
cat >"$fakebin/mise" <<'EOF'
#!/bin/sh
if [ "${1:-}" = env ]; then printf 'export MISE_ENV_APPLIED=1\n'; fi
EOF
cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/zsh" <<'EOF'
#!/bin/sh
if [ "${ZSH_EARLY_EXIT:-0}" = 1 ]; then
  printf '%s\n' "$*" >"$ZSH_ARGUMENTS"
  exit 27
fi
exec /bin/zsh "$@"
EOF
cat >"$fakebin/docker" <<'EOF'
#!/bin/sh
case "$*" in
  info) exit 0 ;;
  'compose build tailscale')
    printf 'build\n' >>"$PREPARATION_COUNT"
    case "${PREPARATION_MODE:-immediate}" in
      immediate) exit 0 ;;
      gate)
        : >"$PREPARATION_STARTED"
        IFS= read -r _ <"$PREPARATION_GATE"
        ;;
      stubborn)
        trap '' HUP INT TERM
        sh -c 'trap "" HUP INT TERM; printf "%s\n" "$$" >"$STUBBORN_DESCENDANT"; while :; do sleep 1; done' &
        printf '%s\n' "$!" >"$STUBBORN_CHILD"
        wait
        ;;
    esac
    ;;
  'compose pull gost gost-ui') exit 0 ;;
  'compose up -d --no-build') : >"$SERVICES_STARTED" ;;
  'compose ps --status running --services') printf 'tailscale\ngost\ngost-ui\n' ;;
  'compose exec -T tailscale tailscale status --json') printf '{"BackendState":"Running"}\n' ;;
esac
EOF
chmod 0755 "$fakebin"/*

wait_for_file() {
  local file=$1 process=$2 attempt
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -e $file ]] && return 0
    kill -0 "$process" 2>/dev/null || break
    sleep 0.02
  done
  printf 'timed out waiting for %s\n' "$file" >&2
  return 1
}

wait_for_exit() {
  local process=$1 attempt
  for ((attempt = 0; attempt < 140; attempt++)); do
    kill -0 "$process" 2>/dev/null || return 0
    sleep 0.05
  done
  printf 'process did not exit within cancellation bound: %s\n' "$process" >&2
  return 1
}

assert_runtime_clean() {
  [[ -z $(find "$runtime" -maxdepth 1 -name 'codyssey-init-preparation.*' -print -quit) ]]
}

# Externally supplied legacy state must remain untouched and cannot suppress a new owned worker.
sentinel="$tmp/sentinel"
mkdir -p "$sentinel"
printf 'keep\n' >"$sentinel/keep"
printf '0\n' >"$sentinel/result"
: >"$sentinel/ready"
: >"$sentinel/log"
sleep 30 &
sentinel_pid=$!
test_processes="$sentinel_pid"
PREPARATION_MODE=immediate PREPARATION_COUNT="$tmp/poison-count" SERVICES_STARTED="$tmp/poison-services" \
STUBBORN_DESCENDANT="$tmp/unused-descendant" STUBBORN_CHILD="$tmp/unused-child" \
HOME="$tmp/home" TMPDIR="$runtime" PATH="$fakebin:/usr/bin:/bin" TS_AUTHKEY='' \
CODYSSEY_PREPARATION_DIR="$sentinel" CODYSSEY_PREPARATION_LOG="$sentinel/log" \
CODYSSEY_PREPARATION_RESULT="$sentinel/result" CODYSSEY_PREPARATION_READY="$sentinel/ready" \
CODYSSEY_PREPARATION_PID="$sentinel_pid" CODYSSEY_INTERACTIVE_SHELL=0 CODYSSEY_OPEN_BROWSER=0 \
zsh "$work/next-script.zsh" >"$tmp/poison.out" 2>&1
kill -TERM "$sentinel_pid"
wait "$sentinel_pid" 2>/dev/null || true
test_processes=
[[ -f $sentinel/keep && $(wc -l <"$tmp/poison-count") -eq 1 && -e $tmp/poison-services ]]
assert_runtime_clean

# Invalid arguments fail before preparation starts.
set +e
PREPARATION_COUNT="$tmp/argument-count" HOME="$tmp/home" TMPDIR="$runtime" PATH="$fakebin:/usr/bin:/bin" \
  zsh "$work/next-script.zsh" unexpected >"$tmp/argument.out" 2>&1
argument_status=$?
set -e
[[ $argument_status -eq 2 && ! -e $tmp/argument-count ]]
grep -q 'Usage: zsh next-script.zsh \[--prepared\]' "$tmp/argument.out"

# Init completes preparation before an explicitly prepared zsh may exit early.
set +e
PREPARATION_MODE=immediate PREPARATION_COUNT="$tmp/early-count" SERVICES_STARTED="$tmp/early-services" \
STUBBORN_DESCENDANT="$tmp/unused-descendant" STUBBORN_CHILD="$tmp/unused-child" \
ZSH_EARLY_EXIT=1 ZSH_ARGUMENTS="$tmp/zsh-arguments" HOME="$tmp/early-home" TMPDIR="$runtime" \
PATH="$fakebin:/usr/bin:/bin" TS_AUTHKEY='' CODYSSEY_OPEN_BROWSER=0 \
bash "$work/init.sh" >"$tmp/early.out" 2>&1
early_status=$?
set -e
[[ $early_status -eq 27 && $(wc -l <"$tmp/early-count") -eq 1 ]]
grep -q -- '--prepared' "$tmp/zsh-arguments"
assert_runtime_clean

# TERM-ignoring compose descendants are killed and reaped within the cancellation bound.
PREPARATION_MODE=stubborn PREPARATION_COUNT="$tmp/stubborn-count" SERVICES_STARTED="$tmp/stubborn-services" \
STUBBORN_DESCENDANT="$tmp/stubborn-descendant" STUBBORN_CHILD="$tmp/stubborn-child" \
HOME="$tmp/home" TMPDIR="$runtime" PATH="$fakebin:/usr/bin:/bin" TS_AUTHKEY='' \
CODYSSEY_INTERACTIVE_SHELL=0 CODYSSEY_OPEN_BROWSER=0 \
zsh "$work/next-script.zsh" >"$tmp/stubborn.out" 2>&1 &
stubborn_pid=$!
test_processes="$stubborn_pid"
wait_for_file "$tmp/stubborn-descendant" "$stubborn_pid"
kill -TERM "$stubborn_pid"
wait_for_exit "$stubborn_pid"
set +e
wait "$stubborn_pid"
stubborn_status=$?
set -e
test_processes=
[[ $stubborn_status -eq 143 && ! -e $tmp/stubborn-services ]]
descendant_pid=$(cat "$tmp/stubborn-descendant")
! kill -0 "$descendant_pid" 2>/dev/null
assert_runtime_clean

# A signal at the silent auth prompt restores the exact PTY state and cancels preparation.
real_stty=$(command -v stty)
cat >"$fakebin/stty" <<EOF
#!/bin/sh
if [ "\${1:-}" = -echo ]; then : >"\$AUTH_ECHO_DISABLED"; fi
exec "$real_stty" "\$@"
EOF
chmod 0755 "$fakebin/stty"
auth_input="$tmp/auth-input"
auth_gate="$tmp/auth-gate"
mkfifo "$auth_input" "$auth_gate"
exec 7<>"$auth_input"
AUTH_ECHO_DISABLED="$tmp/auth-echo-disabled" PREPARATION_MODE=gate PREPARATION_GATE="$auth_gate" \
PREPARATION_STARTED="$tmp/auth-preparation-started" PREPARATION_COUNT="$tmp/auth-count" \
SERVICES_STARTED="$tmp/auth-services" STUBBORN_DESCENDANT="$tmp/unused-descendant" \
STUBBORN_CHILD="$tmp/unused-child" HOME="$tmp/auth-home" TMPDIR="$runtime" PATH="$fakebin:/usr/bin:/bin" \
CODYSSEY_INTERACTIVE_SHELL=0 CODYSSEY_OPEN_BROWSER=0 AUTH_CHILD_PID="$tmp/auth-child-pid" \
AUTH_TTY_RESTORED="$tmp/auth-tty-restored" script -q -e -c \
"before=\$(stty -g); bash '$work/init.sh' & child=\$!; printf '%s\\n' \"\$child\" >'$tmp/auth-child-pid'; wait \"\$child\"; result=\$?; after=\$(stty -g); [ \"\$before\" = \"\$after\" ] && : >'$tmp/auth-tty-restored'; exit \"\$result\"" \
/dev/null <"$auth_input" >"$tmp/auth.out" 2>&1 &
auth_script_pid=$!
test_processes="$auth_script_pid"
printf 'n\n' >&7
wait_for_file "$tmp/auth-echo-disabled" "$auth_script_pid"
auth_child_pid=$(cat "$tmp/auth-child-pid")
kill -TERM "$auth_child_pid"
wait_for_exit "$auth_script_pid"
set +e
wait "$auth_script_pid"
auth_status=$?
set -e
test_processes=
exec 7>&-
[[ $auth_status -eq 143 && -e $tmp/auth-tty-restored && ! -e $tmp/auth-services ]]
assert_runtime_clean
