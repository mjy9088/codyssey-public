#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$root/tunnel-ui"
work=$(mktemp -d)
container=
cleanup() {
  if [ -n "$container" ]; then docker rm "$container" >/dev/null; fi
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# The pristine fixture is read separately by the browser check. No real config or containers are opened.
image=$(awk '/image: gogost\/gost:/{print $2; exit}' "$root/docker-compose.yml")
case "$image" in gogost/gost:3.2.6@sha256:*) ;; *) printf 'Expected the pinned GOST image.\n' >&2; exit 1 ;; esac
container=$(docker create --network none "$image")
docker cp "$container:/bin/gost" "$work/gost"
npm ci --ignore-scripts --no-audit --no-fund
npm run typecheck
npm test
npm run build

mkdir -p "$work/tests/fixtures" "$work/tunnel-ui/test-artifacts" test-artifacts
cp "$root/tests/fixtures/gost.yaml" "$work/tests/fixtures/"
cp -R dist server test index.html node_modules "$work/tunnel-ui/"
browser='mcr.microsoft.com/playwright:v1.61.1-noble@sha256:5b8f294aff9041b7191c34a4bab3ac270157a28774d4b0660e9743297b697e48'
docker run --rm --network none --shm-size 256m --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$work,dst=/case,readonly" \
  --mount "type=bind,src=$PWD/test-artifacts,dst=/case/tunnel-ui/test-artifacts" \
  --workdir /case/tunnel-ui --env GOST_BIN=/case/gost --env HOME=/tmp \
  "$browser" node --test test/browser.test.mjs
