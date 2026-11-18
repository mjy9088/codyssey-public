#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT INT TERM
mkdir "$temporary/bin"
calls=$temporary/calls
signal_marker=$temporary/signal-sent

cat >"$temporary/bin/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$VERIFY_CALLS"
case " $* " in
  *" build "*)
    if test -n "${VERIFY_SIGNAL:-}" && test ! -e "$VERIFY_SIGNAL_MARKER"; then
      : >"$VERIFY_SIGNAL_MARKER"
      trap 'printf "%s\n" "build terminated" >>"$VERIFY_CALLS"; exit 143' TERM
      kill -s "$VERIFY_SIGNAL" "$PPID"
      if test "${VERIFY_BLOCK_BUILD:-0}" -eq 1; then
        while :; do sleep 1; done
      fi
    fi
    ;;
  *" run "*" vm "*)
    printf 'VM-TEST-SUCCESS\r\n'
    exit "${VERIFY_VM_STATUS:-0}"
    ;;
  *" run "*) printf '%s\n' '"Alice Example"' 'used_memory:19' ;;
esac
exit 0
EOF
chmod +x "$temporary/bin/docker"

run_verify() {
  env PATH="$temporary/bin:$PATH" VERIFY_CALLS="$calls" \
    VERIFY_SIGNAL_MARKER="$signal_marker" "$@" sh "$root/scripts/verify.sh" docker
}

: >"$calls"
set +e
env PATH="$temporary/bin:$PATH" VERIFY_CALLS="$calls" \
  VERIFY_SIGNAL_MARKER="$signal_marker" sh "$root/scripts/verify.sh" docker extra \
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
      case " $call " in *" down "*|*" build terminated "*) ;; *) exit 1 ;; esac
    fi
    case " $call " in *" build "*) build_seen=true ;; esac
  done <"$calls"
  test "$build_seen" = true
  test "$calls_after_build" -ge 1
done

: >"$calls"
rm -f "$signal_marker"
set +e
run_verify VERIFY_SIGNAL=TERM VERIFY_BLOCK_BUILD=1 >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 143
grep -Fxq 'build terminated' "$calls"
test "$(grep -c ' down ' "$calls")" -eq 1

set +e
output=$(env PATH="$temporary/bin:$PATH" VERIFY_CALLS="$calls" VERIFY_VM_STATUS=42 \
  sh "$root/scripts/verify.sh" vm)
status=$?
set -e
test "$status" -eq 42
printf '%s\n' "$output" | grep -Fxq 'VM-TEST-SUCCESS'
if printf '%s\n' "$output" | grep -Fxq 'VM-VERIFY-SUCCESS'; then exit 1; fi

printf 'VERIFY-LIFECYCLE-SUCCESS (argc, signals, cleanup-once, VM runner failure)\n'
