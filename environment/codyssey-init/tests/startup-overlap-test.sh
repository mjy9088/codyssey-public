#!/usr/bin/env bash
set -euo pipefail

root=${TEST_ROOT:-/src}
tmp=$(mktemp -d)
test_processes=
cleanup_test() {
  local process
  for process in $test_processes; do
    kill -TERM "$process" 2>/dev/null || true
    wait "$process" 2>/dev/null || true
  done
  rm -rf "$tmp"
}
trap cleanup_test EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
work="$tmp/work"
cp -R "$root/." "$work"
fakebin="$tmp/bin"
mkdir -p "$fakebin" "$tmp/runtime"

cat >"$fakebin/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'x86_64\n' ;;
esac
EOF
cat >"$fakebin/mise" <<'EOF'
#!/bin/sh
if [ "${1:-}" = env ]; then printf 'export MISE_ENV_APPLIED=1\n'; fi
if [ "${1:-}" = install ] && [ -n "${PREPARATION_FINISHED:-}" ]; then : >"$PREPARATION_FINISHED"; fi
EOF
cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
export REAL_STTY=$(command -v stty)
cat >"$fakebin/stty" <<'EOF'
#!/bin/sh
"$REAL_STTY" "$@"
stty_status=$?
if [ "$stty_status" -eq 0 ] && [ "${1:-}" = -echo ] && [ -n "${AUTH_INPUT_READY:-}" ]; then
  printf 'auth-ready\n' >>"$INPUT_EVENT_LOG"
  : >"$AUTH_INPUT_READY"
fi
exit "$stty_status"
EOF
cat >"$fakebin/zsh" <<'EOF'
#!/bin/sh
if [ -n "${ZSH_LOG:-}" ]; then
  printf '<zsh>' >>"$ZSH_LOG"
  for argument in "$@"; do printf '<%s>' "$argument" >>"$ZSH_LOG"; done
  printf '\n' >>"$ZSH_LOG"
fi
exec /bin/zsh "$@"
EOF
cat >"$fakebin/docker" <<'EOF'
#!/bin/sh
case "$*" in
  info) exit 0 ;;
  'compose build tailscale')
    [ -z "${PREPARATION_COUNT:-}" ] || printf 'build\n' >>"$PREPARATION_COUNT"
    : >"$PREPARATION_STARTED"
    printf '%s:%s\n' "${TS_AUTHKEY+x}" "${TS_AUTHKEY:-}" >"$PREPARATION_AUTH"
    printf '%s\n' "$$" >"$PREPARATION_CHILD_PID"
    printf 'buffered preparation output\n'
    trap ': >"$PREPARATION_TERMINATED"; exit 143' HUP INT TERM
    if [ "${PREPARATION_MODE:-success}" = failure ]; then
      [ -z "${PREPARATION_FAILED:-}" ] || : >"$PREPARATION_FAILED"
      printf 'synthetic preparation failure\n' >&2
      exit 19
    fi
    if [ "${PREPARATION_MODE:-success}" = immediate ]; then exit 0; fi
    IFS= read -r _ <"$PREPARATION_GATE"
    ;;
  'compose pull gost gost-ui') : >"$PULL_COMPLETED" ;;
  'compose up -d --no-build') : >"$SERVICES_STARTED" ;;
  'compose ps --status running --services') printf 'tailscale\ngost\ngost-ui\n' ;;
  'compose exec -T tailscale tailscale status --json') printf '{"BackendState":"Running"}\n' ;;
esac
EOF
chmod 0755 "$fakebin"/*

wait_for_file() {
  local file=$1 process=$2 attempt
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ ! -e $file ]] || return 0
    kill -0 "$process" 2>/dev/null || break
    sleep 0.02
  done
  printf 'timed out waiting for synchronization file: %s\n' "$file" >&2
  return 1
}

assert_no_preparation_artifacts() {
  local artifact
  artifact=$(find "$tmp/runtime" -maxdepth 1 -name 'codyssey-init-preparation.*' -print -quit)
  [[ -z $artifact ]] || {
    printf 'private preparation artifact was not removed: %s\n' "$artifact" >&2
    return 1
  }
}

# Preparation must run while each foreground prompt owns the terminal. Inputs are
# released only after the corresponding synchronization marker is observed.
home="$tmp/home"
mkdir -p "$home"
cat >"$work/macos-setup.sh" <<'EOF'
#!/bin/sh
: >"$DOCK_PROMPTED"
IFS= read -r _ </dev/tty
: >"$DOCK_ANSWERED"
printf 'dock-answered\n' >>"$INPUT_EVENT_LOG"
EOF
chmod 0755 "$work/macos-setup.sh"
input="$tmp/input"
gate="$tmp/preparation-gate"
mkfifo "$input" "$gate"
exec 9<>"$input"
PREPARATION_STARTED="$tmp/preparation-started" PREPARATION_TERMINATED="$tmp/preparation-terminated" \
PULL_COMPLETED="$tmp/pull-completed" SERVICES_STARTED="$tmp/services-started" PREPARATION_GATE="$gate" \
PREPARATION_AUTH="$tmp/preparation-auth" PREPARATION_CHILD_PID="$tmp/preparation-child-pid" \
PREPARATION_COUNT="$tmp/preparation-count" PREPARATION_FINISHED="$tmp/preparation-finished" \
DOCK_PROMPTED="$tmp/dock-prompted" DOCK_ANSWERED="$tmp/dock-answered" \
AUTH_INPUT_READY="$tmp/auth-input-ready" INPUT_EVENT_LOG="$tmp/input-events" \
HOME="$home" ZDOTDIR="$home" TMPDIR="$tmp/runtime" PATH="$fakebin:/usr/bin:/bin" \
ZSH_LOG="$tmp/zsh.log" \
CODYSSEY_INTERACTIVE_SHELL=0 CODYSSEY_OPEN_BROWSER=0 \
script -q -e -c "bash '$work/init.sh'" /dev/null <"$input" >"$tmp/interactive.out" 2>&1 &
interactive_pid=$!
test_processes="$interactive_pid"
wait_for_file "$tmp/preparation-started" "$interactive_pid"
wait_for_file "$tmp/pull-completed" "$interactive_pid"
grep -qx 'x:' "$tmp/preparation-auth"
[[ ! -e $tmp/services-started ]]
[[ ! -e $tmp/dock-prompted ]]
printf 'n\n' >&9
wait_for_file "$tmp/dock-prompted" "$interactive_pid"
[[ ! -e $tmp/services-started ]]
printf '\n' >&9
wait_for_file "$tmp/dock-answered" "$interactive_pid"
wait_for_file "$tmp/auth-input-ready" "$interactive_pid"
[[ $(sed -n '1p' "$tmp/input-events") == dock-answered ]]
[[ $(sed -n '2p' "$tmp/input-events") == auth-ready ]]
secret=tskey''-auth-synthetic_overlap_value
printf 'secret-sent\n' >>"$tmp/input-events"
printf '%s\n' "$secret" >&9
wait_for_file "$work/.env" "$interactive_pid" || {
  set +e
  wait "$interactive_pid"
  printf 'interactive exit: %s\n' "$?" >&2
  set -e
  cat "$tmp/interactive.out" >&2
  find "$tmp" -name .env -print >&2
  exit 1
}
[[ ! -e $tmp/services-started ]]
printf 'continue\n' >"$gate"
wait "$interactive_pid"
test_processes=
exec 9>&-
[[ -e $tmp/pull-completed && -e $tmp/services-started ]]
[[ $(sed -n '3p' "$tmp/input-events") == secret-sent ]]
[[ $(wc -l <"$tmp/preparation-count") -eq 1 ]]
grep -Fq '<--prepared>' "$tmp/zsh.log" || {
  cat "$tmp/zsh.log" >&2
  exit 1
}
if grep -Fq "$secret" "$tmp/interactive.out"; then
  printf 'auth key leaked to terminal output\n' >&2
  exit 1
fi
if grep -q 'buffered preparation output' "$tmp/interactive.out"; then
  printf 'background preparation output interleaved with terminal prompts\n' >&2
  exit 1
fi
grep -q 'codyssey-init: starting background preparation.' "$tmp/interactive.out"
grep -q 'codyssey-init: waiting for preparation.' "$tmp/interactive.out"
grep -q 'codyssey-init: preparation complete.' "$tmp/interactive.out"
assert_no_preparation_artifacts

# A completed worker remains owned by init while the j and Dock prompts are unanswered.
run_completed_prompt_case() {
  local mode=$1 expected_status=$2 case_dir case_work case_input case_pid case_status marker
  case_dir="$tmp/prompt-$mode"
  case_work="$case_dir/work"
  mkdir -p "$case_dir"
  cp -R "$root/." "$case_work"
  cat >"$case_work/macos-setup.sh" <<'EOF'
#!/bin/sh
: >"$DOCK_PROMPTED"
IFS= read -r _ </dev/tty
EOF
  chmod 0755 "$case_work/macos-setup.sh"
  case_input="$case_dir/input"
  mkfifo "$case_input"
  exec 8<>"$case_input"
  if [[ $mode == immediate ]]; then marker="$case_dir/preparation-finished"; else marker="$case_dir/preparation-failed"; fi
  PREPARATION_MODE="$mode" PREPARATION_STARTED="$case_dir/preparation-started" \
  PREPARATION_FAILED="$case_dir/preparation-failed" PREPARATION_FINISHED="$case_dir/preparation-finished" \
  PREPARATION_TERMINATED="$case_dir/preparation-terminated" PULL_COMPLETED="$case_dir/pull-completed" \
  SERVICES_STARTED="$case_dir/services-started" PREPARATION_GATE="$case_dir/unused-gate" \
  PREPARATION_AUTH="$case_dir/preparation-auth" PREPARATION_CHILD_PID="$case_dir/preparation-child-pid" \
  PREPARATION_COUNT="$case_dir/preparation-count" DOCK_PROMPTED="$case_dir/dock-prompted" \
  HOME="$case_dir/home" ZDOTDIR="$case_dir/home" TMPDIR="$tmp/runtime" PATH="$fakebin:/usr/bin:/bin" \
  ZSH_LOG="$case_dir/zsh.log" CODYSSEY_INTERACTIVE_SHELL=0 CODYSSEY_OPEN_BROWSER=0 \
  script -q -e -c "bash '$case_work/init.sh'" /dev/null <"$case_input" >"$case_dir/output" 2>&1 &
  case_pid=$!
  test_processes="$case_pid"
  wait_for_file "$marker" "$case_pid"
  [[ ! -e $case_dir/dock-prompted && ! -e $case_dir/services-started ]]
  printf 'n\n' >&8
  wait_for_file "$case_dir/dock-prompted" "$case_pid"
  printf '\n\n' >&8
  set +e
  wait "$case_pid"
  case_status=$?
  set -e
  test_processes=
  exec 8>&-
  [[ $case_status -eq $expected_status ]]
  [[ $(wc -l <"$case_dir/preparation-count") -eq 1 ]]
  [[ -f $case_work/.env ]]
  if [[ $expected_status -eq 0 ]]; then
    [[ -e $case_dir/services-started ]]
    grep -Fq '<--prepared>' "$case_dir/zsh.log"
    grep -q 'codyssey-init: preparation complete.' "$case_dir/output"
  else
    [[ ! -e $case_dir/services-started && ! -e $case_dir/zsh.log ]]
    grep -q 'startup preparation failed (exit 19)' "$case_dir/output"
  fi
  assert_no_preparation_artifacts
}

run_completed_prompt_case immediate 0
run_completed_prompt_case failure 19

# A failed preparation must fail before service startup and remove its private log.
rm -f "$tmp/preparation-started" "$tmp/services-started"
failure_gate="$tmp/failure-gate"
mkfifo "$failure_gate"
if PREPARATION_MODE=failure PREPARATION_STARTED="$tmp/preparation-started" \
  PREPARATION_TERMINATED="$tmp/preparation-terminated" PULL_COMPLETED="$tmp/pull-completed" \
  SERVICES_STARTED="$tmp/services-started" PREPARATION_GATE="$failure_gate" \
  PREPARATION_AUTH="$tmp/preparation-auth" PREPARATION_CHILD_PID="$tmp/preparation-child-pid" \
  HOME="$home" TMPDIR="$tmp/runtime" PATH="$fakebin:/usr/bin:/bin" TS_AUTHKEY='' \
  CODYSSEY_INTERACTIVE_SHELL=0 CODYSSEY_OPEN_BROWSER=0 \
  zsh "$work/next-script.zsh" >"$tmp/failure.out" 2>&1; then
  printf 'failed preparation incorrectly succeeded\n' >&2
  exit 1
fi
[[ ! -e $tmp/services-started ]]
grep -q 'synthetic preparation failure' "$tmp/failure.out"
assert_no_preparation_artifacts

# A signal must reach the blocked preparation command and leave no worker behind.
rm -f "$tmp/preparation-started" "$tmp/preparation-terminated" "$tmp/services-started"
signal_gate="$tmp/signal-gate"
mkfifo "$signal_gate"
PREPARATION_STARTED="$tmp/preparation-started" PREPARATION_TERMINATED="$tmp/preparation-terminated" \
PULL_COMPLETED="$tmp/pull-completed" SERVICES_STARTED="$tmp/services-started" PREPARATION_GATE="$signal_gate" \
PREPARATION_AUTH="$tmp/preparation-auth" PREPARATION_CHILD_PID="$tmp/preparation-child-pid" \
HOME="$home" TMPDIR="$tmp/runtime" PATH="$fakebin:/usr/bin:/bin" TS_AUTHKEY='' \
CODYSSEY_INTERACTIVE_SHELL=0 CODYSSEY_OPEN_BROWSER=0 \
zsh "$work/next-script.zsh" >"$tmp/signal.out" 2>&1 &
signal_pid=$!
test_processes="$signal_pid"
wait_for_file "$tmp/preparation-started" "$signal_pid"
kill -TERM "$signal_pid"
set +e
wait "$signal_pid"
signal_status=$?
set -e
test_processes=
[[ $signal_status -eq 143 ]]
[[ ! -e $tmp/services-started ]]
[[ -e $tmp/preparation-terminated ]]
preparation_child_pid=$(cat "$tmp/preparation-child-pid")
if kill -0 "$preparation_child_pid" 2>/dev/null; then
  printf 'preparation child survived cancellation: %s\n' "$preparation_child_pid" >&2
  exit 1
fi
assert_no_preparation_artifacts
