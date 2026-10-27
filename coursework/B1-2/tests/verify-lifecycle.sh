#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT INT TERM
mkdir "$temporary/bin"
mkdir -p "$temporary/project/scripts"
cp "$root/scripts/verify.sh" "$temporary/project/scripts/verify.sh"
calls=$temporary/calls
signal_marker=$temporary/signal-sent

cat >"$temporary/bin/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$VERIFY_CALLS"
case " $* " in
  *" build "*)
    if test -n "${VERIFY_SIGNAL:-}" && test ! -e "$VERIFY_SIGNAL_MARKER"; then
      : >"$VERIFY_SIGNAL_MARKER"
      kill -s "$VERIFY_SIGNAL" "$PPID"
    fi
    ;;
esac
case " $* " in *" run "*) exit "${VERIFY_RUN_EXIT:-0}" ;; esac
exit 0
EOF
chmod +x "$temporary/bin/docker"

run_verify() {
  env PATH="$temporary/bin:$PATH" VERIFY_CALLS="$calls" \
    VERIFY_SIGNAL_MARKER="$signal_marker" "$@" sh "$temporary/project/scripts/verify.sh" docker
}

: >"$calls"
set +e
env PATH="$temporary/bin:$PATH" VERIFY_CALLS="$calls" \
  VERIFY_SIGNAL_MARKER="$signal_marker" sh "$temporary/project/scripts/verify.sh" docker extra \
  >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 2
test ! -s "$calls"

for signal in INT TERM; do
  : >"$calls"
  rm -f "$signal_marker"
  set +e
  run_verify VERIFY_SIGNAL="$signal" >/dev/null 2>&1
  status=$?
  set -e
  case "$signal:$status" in INT:130|TERM:143) ;; *) exit 1 ;; esac
  test "$(grep -c ' down ' "$calls")" -eq 1
  build_seen=false
  calls_after_build=0
  while IFS= read -r call; do
    if [ "$build_seen" = true ]; then
      calls_after_build=$((calls_after_build + 1))
      case "$calls_after_build:$call" in
        1:*" logs --no-color firebase web") ;;
        "2:rm -f benchbook-docker-"*"-check") ;;
        3:*" down --volumes --remove-orphans") ;;
        *) exit 1 ;;
      esac
    fi
    case " $call " in *" build "*) build_seen=true ;; esac
  done <"$calls"
  test "$build_seen" = true
  test "$calls_after_build" -eq 3
done

for expected in 0 7; do
  : >"$calls"
  set +e
  run_verify VERIFY_RUN_EXIT="$expected" >/dev/null 2>&1
  status=$?
  set -e
  test "$status" -eq "$expected"
  run_seen=false
  calls_after_run=0
  while IFS= read -r call; do
    if [ "$run_seen" = true ]; then
      calls_after_run=$((calls_after_run + 1))
      case "$calls_after_run:$call" in
        1:"cp benchbook-docker-"*"-check:/work/artifacts/. "*) ;;
        2:*" logs --no-color firebase web") ;;
        "3:rm -f benchbook-docker-"*"-check") ;;
        4:*" down --volumes --remove-orphans") ;;
        *) exit 1 ;;
      esac
    fi
    case " $call " in *" run "*) run_seen=true ;; esac
  done <"$calls"
  test "$run_seen" = true
  test "$calls_after_run" -eq 4
done

printf 'VERIFY-LIFECYCLE-SUCCESS (argc, INT=130, TERM=143, artifact-before-cleanup, run-status)\n'
