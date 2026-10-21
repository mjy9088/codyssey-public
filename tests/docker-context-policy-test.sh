#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
temporary=$(mktemp -d)
image="repository-context-probe-$$"
cleanup() {
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -rf "$temporary"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cat >"$temporary/probe.Dockerfile" <<'EOF'
FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
COPY . /context/
RUN (test -f /context/verify/check.sh || test -f /context/tailscale-entrypoint.sh) \
 && test ! -e /context/.env \
 && test ! -e /context/.env.local \
 && test ! -e /context/.local/input.zip \
 && test ! -e /context/.git/config \
 && test ! -e /context/verify/unsafe/.env.production \
 && test ! -e /context/tests/unsafe/private.key \
 && test ! -e /context/src/unsafe/private.pem
EOF
count=0
for area in coursework environment; do
  test ! -L "$root/$area" || { printf 'Refusing symlinked project area: %s\n' "$area" >&2; exit 1; }
  for project in "$root/$area"/*; do
    test ! -L "$project" || { printf 'Refusing symlinked project: %s\n' "$project" >&2; exit 1; }
    test -f "$project/Dockerfile" || continue
    test -f "$project/.dockerignore" && test ! -L "$project/.dockerignore" || {
      printf 'Missing regular Docker context policy: %s\n' "$project" >&2
      exit 1
    }
    context=$(mktemp -d "$temporary/context.XXXXXX")
    cp "$project/.dockerignore" "$context/.dockerignore"
    for file in verify/check.sh tailscale-entrypoint.sh .env .env.local .local/input.zip \
      .git/config verify/unsafe/.env.production tests/unsafe/private.key src/unsafe/private.pem; do
      mkdir -p "$context/$(dirname "$file")"
      printf 'synthetic context policy probe\n' >"$context/$file"
    done
    if ! docker build --force-rm --network none --file "$temporary/probe.Dockerfile" \
      --tag "$image" "$context" >"$temporary/build.log" 2>&1; then
      printf 'Docker context policy failed: %s\n' "${project#"$root/"}" >&2
      cat "$temporary/build.log" >&2
      exit 1
    fi
    count=$((count + 1))
  done
done
printf 'Docker context privacy probes passed for %s active projects.\n' "$count"
