#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
context=$(mktemp -d)
image="folio-context-check-$$"
cleanup() {
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -rf "$context"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for file in src/book_catalog/main.py tests/test_app.py scripts/check.sh verify/check.Dockerfile uv.lock package-lock.json; do
  mkdir -p "$context/$(dirname "$file")"
  printf 'synthetic public source probe\n' >"$context/$file"
done
if test -f "$root/.dockerignore"; then cp "$root/.dockerignore" "$context/.dockerignore"; fi
for directory in .git .local .venv node_modules data artifacts __pycache__ .pytest_cache .ruff_cache test-results playwright-report; do
  mkdir -p "$context/$directory"
  printf 'synthetic context probe\n' >"$context/$directory/context-probe"
done
printf 'synthetic only\n' >"$context/.env"
printf 'synthetic only\n' >"$context/fixture-private.key"
cat >"$context/verify/context-test.Dockerfile" <<'EOF'
FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844
COPY . /context/
RUN test -f /context/src/book_catalog/main.py \
 && test -f /context/tests/test_app.py \
 && test -f /context/scripts/check.sh \
 && test -f /context/verify/check.Dockerfile \
 && test -f /context/uv.lock \
 && test -f /context/package-lock.json \
 && test ! -e /context/.env \
 && test ! -e /context/fixture-private.key \
 && for directory in .git .local .venv node_modules data artifacts __pycache__ .pytest_cache .ruff_cache test-results playwright-report; do \
      test ! -e "/context/$directory" || exit 1; \
    done
EOF
docker build --force-rm --network none --file "$context/verify/context-test.Dockerfile" --tag "$image" "$context"
printf 'Build context checks passed: required source paths retained; local state, caches, and secrets excluded\n'
