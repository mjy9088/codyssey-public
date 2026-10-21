#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT INT TERM
calls="$temporary/calls"
fake_bin="$root/tests/fake-docker-bin"
if [ ! -x "$fake_bin/docker" ]; then
  mkdir "$temporary/bin"
  cp "$fake_bin/docker" "$temporary/bin/docker"
  chmod +x "$temporary/bin/docker"
  fake_bin="$temporary/bin"
fi

run_verify() {
  : >"$calls"
  env PATH="$fake_bin:$PATH" ORCHESTRATION_CALLS="$calls" "$@" \
    sh "$root/scripts/verify.sh" docker
}

assert_signal_lifecycle() {
  signal=$1
  expected_status=$2
  marker=$temporary/signal-sent
  rm -f "$marker"
  set +e
  run_verify ORCHESTRATION_SIGNAL="$signal" ORCHESTRATION_SIGNAL_MARKER="$marker" \
    >/dev/null 2>&1
  status=$?
  set -e
  [ "$status" -eq "$expected_status" ]
  [ "$(grep -c ' down ' "$calls")" -eq 1 ]
  browser_build_seen=false
  calls_after_build=0
  while IFS= read -r call; do
    if [ "$browser_build_seen" = true ]; then
      calls_after_build=$((calls_after_build + 1))
      case " $call " in *" down "*) ;; *) return 1 ;; esac
    fi
    case "$call" in
      compose\ *) case " $call " in *" build "*) browser_build_seen=true ;; esac ;;
    esac
  done <"$calls"
  [ "$browser_build_seen" = true ]
  [ "$calls_after_build" -eq 1 ]
}

assert_both_suites_in_order() {
  check_seen=false
  browser_seen=false
  while IFS= read -r call; do
    case "$call" in
      run\ *) check_seen=true ;;
      compose\ *\ run\ *)
        [ "$check_seen" = true ] || {
          printf '%s\n' 'browser verifier ran before the check suite' >&2
          exit 1
        }
        browser_seen=true
        ;;
    esac
  done <"$calls"
  [ "$check_seen" = true ] || {
    printf '%s\n' 'check suite was not run' >&2
    exit 1
  }
  [ "$browser_seen" = true ] || {
    printf '%s\n' 'browser verifier was not run' >&2
    exit 1
  }
}

run_verify
assert_both_suites_in_order

if run_verify CHECK_FAIL=1; then
  printf '%s\n' 'check suite failure was swallowed' >&2
  exit 1
fi
while IFS= read -r call; do
  case "$call" in
    compose\ *\ run\ *)
      printf '%s\n' 'browser verifier ran after the check suite failed' >&2
      exit 1
      ;;
  esac
done <"$calls"

if run_verify BROWSER_FAIL=1; then
  printf '%s\n' 'browser verifier failure was swallowed' >&2
  exit 1
fi
assert_both_suites_in_order

: >"$calls"
set +e
env PATH="$fake_bin:$PATH" ORCHESTRATION_CALLS="$calls" \
  sh "$root/scripts/verify.sh" docker extra >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ]
[ ! -s "$calls" ]
assert_signal_lifecycle INT 130
assert_signal_lifecycle TERM 143
printf 'VERIFY-ORCHESTRATION-SUCCESS (ordering, argc, INT=130, TERM=143, cleanup-once)\n'
