#!/bin/sh
set -eu

mode=${1:-docker}
update=${UPDATE_SNAPSHOTS:-0}
test "$#" -le 1 || { printf 'Too many arguments\n' >&2; exit 2; }
case "$update" in 0|1) ;; *) printf 'UPDATE_SNAPSHOTS must be 0 or 1\n' >&2; exit 2 ;; esac
if [ "$update" = 1 ] && [ "$mode" != docker ]; then
  printf 'Update reference screenshots only with docker mode\n' >&2
  exit 2
fi
case "$mode" in
  --help)
    printf '%s\n' 'Usage: sh scripts/verify.sh [docker|vm|all]' \
      'Requires only Docker Engine, Docker Compose v2, and a POSIX shell.' \
      'Artifacts are copied from the runner, so remote Docker and DinD need no bind mount.' \
      'UPDATE_SNAPSHOTS=1 explicitly refreshes the three reference images in docker mode.'
    exit 0 ;;
  all)
    sh "$0" docker
    exec sh "$0" vm ;;
  docker) server=web ;;
  vm) server=vm ;;
  *) printf 'Unknown verification mode: %s\n' "$mode" >&2; exit 2 ;;
esac

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
project="portfolio-$mode-$$"
runner="$project-check"
output="$root/artifacts/$mode"
compose() { docker compose -p "$project" -f "$root/compose.yaml" --profile verify --profile vm "$@"; }
cleanup() {
  compose logs --no-color "$server" > "$output/server.log" 2>&1 || true
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
docker compose version
compose config --quiet
compose build "$server" verify
compose up -d --wait --wait-timeout 180 "$server"
compose logs --no-color "$server" > "$output/server.log"
if [ "$update" = 1 ]; then set -- --update-snapshots; else set --; fi
if compose run --no-deps --name "$runner" -e "BASE_URL=http://$server:8080" -e "VERIFY_MODE=$mode" verify npm test -- "$@"; then
  result=0
else
  result=$?
fi
docker cp "$runner:/work/artifacts/." "$output/"
if [ "$update" = 1 ] && [ "$result" = 0 ]; then
  docker cp "$runner:/work/docs/screenshots/." "$root/docs/screenshots/"
  printf 'Reference screenshots updated; review the image diff before committing.\n'
fi
printf 'Verification mode=%s exit=%s artifacts=%s\n' "$mode" "$result" "$output"
exit "$result"
