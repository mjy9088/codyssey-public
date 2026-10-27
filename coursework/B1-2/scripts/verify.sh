#!/bin/sh
set -eu
mode=${1:-docker}
test "$#" -le 1 || { printf 'Too many arguments\n' >&2; exit 2; }
case "$mode" in
  --help) printf '%s\n' 'Usage: sh scripts/verify.sh [docker|vm|all]'; exit 0 ;;
  all) sh "$0" docker; exec sh "$0" vm ;;
  docker) server=web ;;
  vm) server=vm ;;
  *) printf 'Unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="benchbook-$mode-$$"
runner="$project-check"
output="$root/artifacts/$mode"
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile verify --profile vm "$@"; }
cleanup() {
  compose logs --no-color firebase "$server" > "$output/server.log" 2>&1 || true
  docker rm -f "$runner" >/dev/null 2>&1 || true
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}
if [ -e "$output" ]; then
  mv "$output" "$output-previous-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi
mkdir -p "$output"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker version >/dev/null
compose config --quiet
compose build firebase "$server" verify
compose up -d --wait --wait-timeout 240 firebase "$server"
if compose run --name "$runner" --no-deps -e "BASE_URL=http://$server:8080" verify; then
  result=0
else
  result=$?
fi
docker cp "$runner:/work/artifacts/." "$output/"
if [ "$mode" = vm ]; then
  compose exec -T vm wget -q -O - http://127.0.0.1:8080/__vm-proof.txt
fi
printf 'Verification mode=%s exit=%s artifacts=%s\n' "$mode" "$result" "$output"
exit "$result"
