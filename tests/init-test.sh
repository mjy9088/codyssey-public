#!/bin/sh
set -eu

root=${INIT_TEST_ROOT:-/src}
tmp=$(mktemp -d)
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' 0 HUP INT TERM
fakebin=$tmp/bin
mkdir -p "$fakebin" "$tmp/home" "$tmp/stage"

fail() {
  printf 'init-test: %s\n' "$*" >&2
  exit 1
}

cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
output=
url=
while [ "$#" -gt 0 ]; do
  case $1 in
    -o) output=$2; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"$FAKE_CURL_LOG"
if [ "${FAKE_CURL_FAIL:-0}" = 1 ]; then
  printf '%s\n' 'touch "$PARTIAL_EXECUTED"' >"$output"
  exit 22
fi
cp "$FAKE_PAYLOAD" "$output"
EOF
cat >"$fakebin/bash" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_BASH_LOG"
exec /bin/sh "$@"
EOF
chmod 0755 "$fakebin/curl" "$fakebin/bash"

payload=$tmp/payload.sh
cat >"$payload" <<'EOF'
#!/bin/sh
printf '%s\n' executed >"$PAYLOAD_RESULT"
exit "${PAYLOAD_STATUS:-0}"
EOF

run_remote() {
  HOME=$tmp/home TMPDIR=$tmp/stage PATH=$fakebin:/usr/bin:/bin \
    FAKE_CURL_LOG=$tmp/curl.log FAKE_BASH_LOG=$tmp/bash.log FAKE_PAYLOAD=$payload \
    PAYLOAD_RESULT=$tmp/result PARTIAL_EXECUTED=$tmp/partial \
    PAYLOAD_STATUS=${TEST_STATUS-0} FAKE_CURL_FAIL=${TEST_FETCH_FAIL-0} \
    /bin/sh <"$root/init.sh"
}

default_base=https://raw.githubusercontent.com/mjy9088/codyssey-public
unset TEST_STATUS TEST_FETCH_FAIL
run_remote >"$tmp/output"
grep -qx executed "$tmp/result" || fail 'default payload variables differ'
grep -qx "$default_base/main/environment/codyssey-init/init.sh" "$tmp/curl.log" || fail 'default fetch URL differs'
[ -z "$(ls -A "$tmp/stage")" ] || fail 'successful run left a temporary installer'

: >"$tmp/bash.log"
: >"$tmp/curl.log"
TEST_STATUS=37
set +e
run_remote >/dev/null
status=$?
set -e
[ "$status" -eq 37 ] || fail 'payload status was not preserved'
[ -z "$(ls -A "$tmp/stage")" ] || fail 'nonzero payload left a temporary installer'

: >"$tmp/bash.log"
: >"$tmp/curl.log"
unset TEST_STATUS
TEST_FETCH_FAIL=1
set +e
run_remote >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 22 ] || fail 'curl failure status was not preserved'
[ ! -s "$tmp/bash.log" ] || fail 'failed download called Bash'
[ ! -e "$tmp/partial" ] || fail 'partial download executed'
[ -z "$(ls -A "$tmp/stage")" ] || fail 'failed download left a temporary installer'

unset TEST_FETCH_FAIL

empty_path=$tmp/empty
mkdir "$empty_path"
PATH=$empty_path /bin/sh "$root/init.sh" --help >"$tmp/help"
grep -q 'Usage: sh init.sh' "$tmp/help" || fail 'help output missing usage'
set +e
PATH=$empty_path /bin/sh "$root/init.sh" --unknown >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail 'unsupported argument did not return status 2'
set +e
PATH=$empty_path /bin/sh "$root/init.sh" --help unexpected >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail 'extra arguments after help were ignored'

fixture=$tmp/local
mkdir -p "$fixture/environment/codyssey-init"
cp "$root/init.sh" "$fixture/init.sh"
cat >"$fixture/environment/codyssey-init/init.sh" <<'EOF'
#!/bin/sh
printf '%s\n' delegated >"$LOCAL_MARKER"
exit 41
EOF
: >"$tmp/bash.log"
: >"$tmp/curl.log"
set +e
HOME=$tmp/home PATH=$fakebin:/usr/bin:/bin FAKE_BASH_LOG=$tmp/bash.log \
  FAKE_CURL_LOG=$tmp/curl.log LOCAL_MARKER=$tmp/local-marker \
  /bin/sh "$fixture/init.sh" >"$tmp/local-output"
status=$?
set -e
[ "$status" -eq 41 ] || fail 'local delegation status was not preserved'
grep -qx delegated "$tmp/local-marker" || fail 'local environment init did not run'
grep -qx "$fixture/environment/codyssey-init/init.sh" "$tmp/bash.log" || fail 'local init path argument differs'
[ ! -s "$tmp/curl.log" ] || fail 'local delegation downloaded content'
set +e
(
  cd "$fixture"
  HOME=$tmp/home PATH=$fakebin:/usr/bin:/bin FAKE_BASH_LOG=$tmp/bash.log \
    FAKE_CURL_LOG=$tmp/curl.log LOCAL_MARKER=$tmp/local-marker sh init.sh
)
status=$?
set -e
[ "$status" -eq 41 ] || fail 'relative init.sh invocation lost local delegation'

collision=$tmp/stdin-collision
mkdir -p "$collision/environment/codyssey-init"
: >"$collision/sh"
cat >"$collision/environment/codyssey-init/init.sh" <<'EOF'
#!/bin/sh
printf 'unexpected local execution\n' >"$COLLISION_LOCAL_MARKER"
EOF
: >"$tmp/bash.log"
: >"$tmp/curl.log"
(
  cd "$collision"
  HOME=$tmp/home TMPDIR=$tmp/stage PATH=$fakebin:/usr/bin:/bin \
    FAKE_CURL_LOG=$tmp/curl.log FAKE_BASH_LOG=$tmp/bash.log FAKE_PAYLOAD=$payload \
    PAYLOAD_RESULT=$tmp/result COLLISION_LOCAL_MARKER=$tmp/collision-local \
    sh <"$root/init.sh"
)
[ ! -e "$tmp/collision-local" ] || fail 'stdin execution delegated to caller-owned checkout code'
grep -qx "$default_base/main/environment/codyssey-init/init.sh" "$tmp/curl.log" || fail 'stdin execution did not fetch the remote bootstrap'

printf '%s\n' 'Root init checks passed.'
