#!/bin/bash

readonly HELLO_WORLD_IMAGE="hello-world:latest@sha256:c3cbe1cc1aa588a64951ac6286e0df7b27fe2e6324b1001c619bb358770c0178"
readonly NGINX_IMAGE="nginx:1.27-alpine@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10"
readonly UBUNTU_IMAGE="ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90"

begin_validation() {
  local name="$1"
  printf '# Validation: %s\n' "$name"
  trap 'trace_command "$BASH_COMMAND"' DEBUG
}

end_validation() {
  trap - DEBUG
}

trace_command() {
  case "$1" in
    section\ * | end_validation | trap\ * | \[\[\ * ) return 0 ;;
  esac
  printf '\n$ %s\n' "$1" >&2
}

section() {
  printf '\n## %s\n' "$1"
}

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'ASSERT FAIL: %s\n  expected: %q\n  actual:   %q\n' \
      "$label" "$expected" "$actual" >&2
    return 1
  fi
  printf 'ASSERT PASS: %s = %q\n' "$label" "$actual"
}

assert_contains() {
  local label="$1"
  local actual="$2"
  local expected_fragment="$3"

  if [[ "$actual" != *"$expected_fragment"* ]]; then
    printf 'ASSERT FAIL: %s\n  missing: %q\n  actual:  %q\n' \
      "$label" "$expected_fragment" "$actual" >&2
    return 1
  fi
  printf 'ASSERT PASS: %s contains %q\n' "$label" "$expected_fragment"
}

cleanup_container() {
  docker rm -f "$1" >/dev/null 2>&1 || true
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-20}"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --output /dev/null "$url"; then
      printf 'HTTP endpoint ready after %d attempt(s): %s\n' "$attempt" "$url"
      return 0
    fi
    sleep 1
  done

  printf 'HTTP endpoint did not become ready: %s\n' "$url" >&2
  return 1
}

wait_for_container_health() {
  local container="$1"
  local attempts="${2:-20}"
  local health

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    health="$(docker inspect --format '{{.State.Health.Status}}' "$container")"
    if [[ "$health" == "healthy" ]]; then
      printf 'Container healthy after %d attempt(s): %s\n' "$attempt" "$container"
      return 0
    fi
    [[ "$health" == "unhealthy" ]] && break
    sleep 1
  done

  docker inspect --format '{{json .State.Health}}' "$container" >&2
  return 1
}
