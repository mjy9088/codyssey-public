#!/bin/sh
set -eu

root=${1:?candidate root is required}
auto_sentinel="$root/infrastructure/deployment/synthetic-context-secret.auto.tfvars"
json_sentinel="$root/infrastructure/access-bootstrap/synthetic-context-secret.tfvars.json"
image="b3-1-context-test-$$"

if test -e "$auto_sentinel" || test -e "$json_sentinel"; then
  printf 'Synthetic context sentinel path already exists; refusing to overwrite it\n' >&2
  exit 1
fi

cleanup() {
  rm -f "$auto_sentinel" "$json_sentinel"
  docker image rm -f "$image" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

printf 'synthetic_context_value = "benign-auto-sentinel"\n' > "$auto_sentinel"
printf '{"synthetic_context_value":"benign-json-sentinel"}\n' > "$json_sentinel"
docker build --quiet --tag "$image" --file "$root/verify/Dockerfile.context-test" "$root" >/dev/null
printf 'PASS: precise Docker context includes verifier sources and excludes all tfvars forms\n'
