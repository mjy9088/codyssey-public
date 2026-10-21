#!/bin/sh
set -eu

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' 0 HUP INT TERM

fail() {
  printf 'repository-integrity-test: %s\n' "$*" >&2
  exit 1
}

make_valid_fixture() {
  fixture=$1
  mkdir -p "$fixture/docs" "$fixture/coursework/B1" "$fixture/archive/E1"
  : >"$fixture/init.sh"
  : >"$fixture/docs/guide.md"
  : >"$fixture/coursework/B1/Dockerfile"
  : >"$fixture/coursework/B1/.dockerignore"
  : >"$fixture/archive/E1/Dockerfile"
  cat >"$fixture/README.md" <<'EOF'
[guide](docs/guide.md#usage) [section](#local) [site](https://example.test)
[self]( )

```text
[example only](missing.md)
```
EOF
}

expect_failure() {
  fixture=$1
  diagnostic=$2
  set +e
  output=$(/opt/check-repository.sh --scan "$fixture" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "invalid fixture passed: $diagnostic"
  printf '%s\n' "$output" | grep -F "$diagnostic" >/dev/null ||
    fail "missing diagnostic: $diagnostic"
}

valid=$tmp/valid
make_valid_fixture "$valid"
/opt/check-repository.sh --scan "$valid" >"$tmp/valid-output"
grep -F 'Repository integrity checks passed.' "$tmp/valid-output" >/dev/null ||
  fail 'valid fixture did not report success'
/opt/check-repository.sh --help >/dev/null

missing_entrypoint=$tmp/missing-entrypoint
make_valid_fixture "$missing_entrypoint"
rm "$missing_entrypoint/init.sh"
expect_failure "$missing_entrypoint" 'root-entrypoint: missing regular init.sh'

root_entrypoints=$tmp/root-entrypoints
make_valid_fixture "$root_entrypoints"
: >"$root_entrypoints/macos-setup.sh"
: >"$root_entrypoints/enable-korean.swift"
expect_failure "$root_entrypoints" 'root-entrypoint: enable-korean.swift'
expect_failure "$root_entrypoints" 'root-entrypoint: macos-setup.sh'

missing_link=$tmp/missing-link
make_valid_fixture "$missing_link"
printf '%s\n' '[missing](../absent.txt)' >"$missing_link/docs/guide.md"
expect_failure "$missing_link" 'markdown-link: docs/guide.md -> ../absent.txt'

outside_link=$tmp/outside-link
make_valid_fixture "$outside_link"
printf '%s\n' 'private' >"$tmp/outside.txt"
ln -s "$tmp/outside.txt" "$outside_link/outside.txt"
printf '%s\n' '[outside](../outside.txt)' >"$outside_link/docs/guide.md"
expect_failure "$outside_link" 'markdown-link: docs/guide.md -> ../outside.txt'

missing_ignore=$tmp/missing-ignore
make_valid_fixture "$missing_ignore"
rm "$missing_ignore/coursework/B1/.dockerignore"
expect_failure "$missing_ignore" 'docker-context: coursework/B1/.dockerignore'

printf '%s\n' 'Repository integrity fixture checks passed.'
