#!/bin/sh
set -eu

root=/src
tmp=$(mktemp -d)
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
printf '%s|%s\n' "$CODYSSEY_INIT_REF" "$CODYSSEY_INIT_BASE_URL" >"$PAYLOAD_RESULT"
exit "${PAYLOAD_STATUS:-0}"
EOF

run_remote() {
  HOME=$tmp/home TMPDIR=$tmp/stage PATH=$fakebin:/usr/bin:/bin \
    FAKE_CURL_LOG=$tmp/curl.log FAKE_BASH_LOG=$tmp/bash.log FAKE_PAYLOAD=$payload \
    PAYLOAD_RESULT=$tmp/result PARTIAL_EXECUTED=$tmp/partial \
    CODYSSEY_INIT_REF=${TEST_REF-} CODYSSEY_INIT_BASE_URL=${TEST_BASE-} \
    PAYLOAD_STATUS=${TEST_STATUS-0} FAKE_CURL_FAIL=${TEST_FETCH_FAIL-0} \
    /bin/sh <"$root/init.sh"
}

default_ref=95de4b0b882b7f3e15cab05e4d847a01de36c1b9
default_base=https://raw.githubusercontent.com/mjy9088/codyssey-public
unset TEST_REF TEST_BASE TEST_STATUS TEST_FETCH_FAIL
run_remote >"$tmp/output"
grep -qx "$default_ref|$default_base" "$tmp/result" || fail 'default payload variables differ'
grep -qx "$default_base/$default_ref/environment/codyssey-init/init.sh" "$tmp/curl.log" || fail 'default fetch URL differs'
grep -q "$default_base/$default_ref/environment/codyssey-init/README.md" "$tmp/output" || fail 'selected documentation URL missing'
[ -z "$(ls -A "$tmp/stage")" ] || fail 'successful run left a temporary installer'

: >"$tmp/bash.log"
: >"$tmp/curl.log"
TEST_REF=0123456789abcdef0123456789abcdef01234567
TEST_BASE=https://example.invalid/repository/
TEST_STATUS=37
set +e
run_remote >/dev/null
status=$?
set -e
[ "$status" -eq 37 ] || fail 'payload status was not preserved'
grep -qx '0123456789abcdef0123456789abcdef01234567|https://example.invalid/repository' "$tmp/result" || fail 'reviewed overrides were not exported'
grep -qx 'https://example.invalid/repository/0123456789abcdef0123456789abcdef01234567/environment/codyssey-init/init.sh' "$tmp/curl.log" || fail 'override fetch URL differs'
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

unset TEST_FETCH_FAIL TEST_BASE
for TEST_REF in short 0123456789ABCDEF0123456789abcdef01234567; do
  : >"$tmp/curl.log"
  set +e
  run_remote >/dev/null 2>&1
  status=$?
  set -e
  [ "$status" -eq 2 ] || fail 'invalid ref did not return status 2'
  [ ! -s "$tmp/curl.log" ] || fail 'invalid ref reached curl'
done
TEST_REF=$default_ref
TEST_BASE=http://example.invalid/repository
: >"$tmp/curl.log"
set +e
run_remote >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail 'non-HTTPS base did not return status 2'
[ ! -s "$tmp/curl.log" ] || fail 'non-HTTPS base reached curl'

empty_path=$tmp/empty
mkdir "$empty_path"
PATH=$empty_path CODYSSEY_INIT_REF=$default_ref /bin/sh "$root/init.sh" --help >"$tmp/help"
grep -q 'Usage: sh init.sh' "$tmp/help" || fail 'help output missing usage'
PATH=$empty_path CODYSSEY_INIT_REF=$default_ref /bin/sh "$root/init.sh" --docs >"$tmp/docs"
grep -q "$default_ref/environment/codyssey-init/README.md" "$tmp/docs" || fail 'docs output missing selected ref'
set +e
PATH=$empty_path /bin/sh "$root/init.sh" --unknown >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail 'unsupported argument did not return status 2'

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
grep -q 'Using the environment bootstrap from this local checkout.' "$tmp/local-output" || fail 'local guidance missing'

printf '%s\n' 'Root init checks passed.'
