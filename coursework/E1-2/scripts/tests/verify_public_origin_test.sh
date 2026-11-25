#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fixture="$temporary/fixture"
fake_bin="$temporary/bin"
pinned_image='docker.gitea.com/gitea:1.24.7@sha256:918955f16b1e91732af6c449bb2db3a34271748dbed1ccfbae48f8a2fb5480b8'
mkdir -p "$fixture/scripts" "$fake_bin"
cp "$root/scripts/verify_public_origin.sh" "$fixture/scripts/verify_public_origin.sh"

fail() {
    printf 'verify-public-origin-test: %s\n' "$*" >&2
    exit 1
}

cat >"$fake_bin/git" <<'EOF'
#!/bin/sh
printf '<%s>\n' "$@" >>"$GIT_CALLS"
case "$*" in
    *' remote get-url origin') printf '%s\n' "${FAKE_ORIGIN:-https://example.invalid/public.git}" ;;
    'check-ref-format refs/tags/'*) exit "${FAKE_REF_STATUS:-0}" ;;
    *' rev-parse --verify refs/tags/'*) printf '%s\n' '0123456789abcdef0123456789abcdef01234567' ;;
    *) exit 93 ;;
esac
EOF

cat >"$fake_bin/docker" <<'EOF'
#!/bin/sh
printf '<%s>\n' "$@" >>"$DOCKER_CALLS"
exit "${FAKE_DOCKER_STATUS:-0}"
EOF
chmod 0755 "$fake_bin/git" "$fake_bin/docker"

run_verify() {
    : >"$temporary/git.calls"
    : >"$temporary/docker.calls"
    (
        cd "$temporary"
        PATH="$fake_bin:/usr/bin:/bin" \
            GIT_CALLS="$temporary/git.calls" \
            DOCKER_CALLS="$temporary/docker.calls" \
            FAKE_ORIGIN="${FAKE_ORIGIN:-https://example.invalid/public.git}" \
            sh "$fixture/scripts/verify_public_origin.sh" "$@"
    )
}

run_verify >"$temporary/default.out"
grep -Fqx "client_image=$pinned_image" "$temporary/default.out" || fail 'default image is not digest-pinned'
grep -Fqx "<$pinned_image>" "$temporary/docker.calls" || fail 'Docker did not receive the pinned default image'
grep -Fqx '<ORIGIN_URL=https://example.invalid/public.git>' "$temporary/docker.calls" || fail 'Docker did not receive the origin URL as an environment value'
grep -Fqx '<REMOTE_REFS=HEAD refs/heads/main>' "$temporary/docker.calls" || fail 'default public refs differ'

run_verify submission-v1 >"$temporary/tag.out"
grep -Fqx 'tag=submission-v1' "$temporary/tag.out" || fail 'tag output is missing'
grep -Fqx '<REMOTE_REFS=HEAD refs/heads/main refs/tags/submission-v1 refs/tags/submission-v1^{}>' "$temporary/docker.calls" || fail 'tag refs differ'
grep -Fqx '<EXPECTED_REVISION=0123456789abcdef0123456789abcdef01234567>' "$temporary/docker.calls" || fail 'expected tag revision was not passed to Docker'

set +e
run_verify first second >"$temporary/extra.out" 2>"$temporary/extra.err"
status=$?
set -e
[ "$status" -eq 2 ] || fail 'extra arguments did not return status 2'
grep -Fqx 'Usage: sh scripts/verify_public_origin.sh [tag]' "$temporary/extra.err" || fail 'extra arguments did not show usage'
[ ! -s "$temporary/git.calls" ] || fail 'extra arguments reached Git'
[ ! -s "$temporary/docker.calls" ] || fail 'extra arguments reached Docker'

set +e
FAKE_ORIGIN='https://user:secret@example.invalid/public.git' run_verify >"$temporary/credentials.out" 2>"$temporary/credentials.err"
status=$?
set -e
[ "$status" -eq 1 ] || fail 'credential-bearing origin did not fail'
[ ! -s "$temporary/docker.calls" ] || fail 'credential-bearing origin reached Docker'

grep -Fq "$pinned_image" "$root/docs/evidence/public-origin-access.md" || fail 'documentation does not name the pinned default image'
if grep -Fq 'GIT_CLIENT_IMAGE=${GIT_CLIENT_IMAGE:-docker.gitea.com/gitea:1.24.7}' "$root/scripts/verify_public_origin.sh"; then
    fail 'mutable image default remains in the verifier'
fi

printf '%s\n' 'E1-2 public origin verifier checks passed.'
