#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fixture="$temporary/fixture"
fake_bin="$temporary/bin"
mkdir -p "$fixture" "$fake_bin"
cp "$root/lab.bash" "$fixture/lab.bash"

fail() {
  printf 'lab-cli-test: %s\n' "$*" >&2
  exit 1
}

cat >"$fake_bin/docker" <<'EOF'
#!/bin/sh
printf '%s|%s\n' "$PWD" "$*" >>"$DOCKER_CALLS"
if [ "$*" = 'compose exec -T workstation docker info' ]; then
  count=0
  [ ! -f "$READY_COUNT" ] || count=$(cat "$READY_COUNT")
  count=$((count + 1))
  printf '%s\n' "$count" >"$READY_COUNT"
  [ "$count" -ge "${FAKE_READY_AFTER:-1}" ]
fi
EOF

cat >"$fake_bin/sleep" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SLEEP_CALLS"
EOF
chmod 0755 "$fake_bin/docker" "$fake_bin/sleep"

run_lab() {
  : >"$temporary/docker.calls"
  : >"$temporary/sleep.calls"
  rm -f "$temporary/ready.count"
  (
    cd "$temporary"
    PATH="$fake_bin:/usr/bin:/bin" \
      DOCKER_CALLS="$temporary/docker.calls" \
      SLEEP_CALLS="$temporary/sleep.calls" \
      READY_COUNT="$temporary/ready.count" \
      FAKE_READY_AFTER="${FAKE_READY_AFTER:-1}" \
      LAB_READY_ATTEMPTS="${LAB_READY_ATTEMPTS:-3}" \
      bash "$fixture/lab.bash" "$@"
  )
}

FAKE_READY_AFTER=2 run_lab up >"$temporary/up.out"
grep -q 'Waiting for the Docker daemon\. ready' "$temporary/up.out" || fail 'successful readiness output differs'
[ "$(wc -l <"$temporary/sleep.calls")" -eq 1 ] || fail 'successful readiness slept the wrong number of times'
[ "$(cat "$temporary/ready.count")" -eq 2 ] || fail 'successful readiness used the wrong attempt count'
grep -Fqx "$fixture|compose up -d --build" "$temporary/docker.calls" || fail 'up did not run from the script directory'

set +e
FAKE_READY_AFTER=99 LAB_READY_ATTEMPTS=3 run_lab up >"$temporary/failure.out" 2>"$temporary/failure.err"
status=$?
set -e
[ "$status" -ne 0 ] || fail 'readiness exhaustion succeeded'
grep -Fq 'did not become ready after 3 attempts' "$temporary/failure.err" || fail 'readiness exhaustion lacked a bounded error'
[ "$(cat "$temporary/ready.count")" -eq 3 ] || fail 'readiness exhaustion used the wrong attempt count'
[ "$(wc -l <"$temporary/sleep.calls")" -eq 2 ] || fail 'readiness exhaustion slept after its final attempt'
grep -Fqx "$fixture|compose ps" "$temporary/docker.calls" || fail 'readiness exhaustion did not show status'

run_lab status >/dev/null
grep -Fqx "$fixture|compose ps" "$temporary/docker.calls" || fail 'status did not run from the script directory'

printf 'RESET\n' | run_lab reset >"$temporary/reset.out"
grep -Fq 'host images and caches remain' "$temporary/reset.out" || fail 'reset prompt overclaims host image deletion'
grep -Fqx "$fixture|compose down --volumes --remove-orphans" "$temporary/docker.calls" || fail 'reset lifecycle command differs'
if grep -Fq -- '--rmi' "$temporary/docker.calls"; then
  fail 'reset removes retained images'
fi

set +e
run_lab status unexpected >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail 'extra arguments did not return status 2'
[ ! -s "$temporary/docker.calls" ] || fail 'extra arguments reached Docker'

set +e
LAB_READY_ATTEMPTS=invalid run_lab status >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail 'invalid readiness configuration did not return status 2'
[ ! -s "$temporary/docker.calls" ] || fail 'invalid readiness configuration reached Docker'

set +e
LAB_READY_ATTEMPTS=0 run_lab status >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail 'zero readiness attempts did not return status 2'
[ ! -s "$temporary/docker.calls" ] || fail 'zero readiness attempts reached Docker'

printf '%s\n' 'E1-1 lab CLI checks passed.'
