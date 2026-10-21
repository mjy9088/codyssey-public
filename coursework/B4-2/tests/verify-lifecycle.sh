#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
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
      kill -s "$VERIFY_SIGNAL" "$PPID"
    fi
    ;;
  *" run "*) printf '%s\n' 'MEMORY-CHECK synthetic' 'CPU-CHECK synthetic' \
    'DEADLOCK-CHECK synthetic' 'SYNTHETIC-LAB-SUCCESS' ;;
esac
exit 0
EOF
chmod +x "$temporary/bin/docker"

run_verify() {
  env PATH="$temporary/bin:$PATH" VERIFY_CALLS="$calls" \
    VERIFY_SIGNAL_MARKER="$signal_marker" "$@" sh "$root/scripts/verify.sh" synthetic-docker
}

: >"$calls"
set +e
env PATH="$temporary/bin:$PATH" VERIFY_CALLS="$calls" \
  VERIFY_SIGNAL_MARKER="$signal_marker" sh "$root/scripts/verify.sh" synthetic-docker extra \
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
      case " $call " in *" down "*) ;; *) exit 1 ;; esac
    fi
    case " $call " in *" build "*) build_seen=true ;; esac
  done <"$calls"
  test "$build_seen" = true
  test "$calls_after_build" -eq 1
done

printf 'VERIFY-LIFECYCLE-SUCCESS (argc, INT=130, TERM=143, cleanup-once)\n'
