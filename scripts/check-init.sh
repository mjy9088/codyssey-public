#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image=codyssey-root-init-check:local
docker version >/dev/null
context=$(mktemp -d)
trap 'rm -rf "$context"' 0 HUP INT TERM
tar -C "$root" -cf - init.sh tests/init-test.sh tests/init.Dockerfile | tar -C "$context" -xf -
docker build --file "$context/tests/init.Dockerfile" --tag "$image" "$context"
docker run --rm --network none --read-only \
  --tmpfs /tmp:rw,exec,size=16m,mode=1777 \
  --env HOME=/tmp/home --security-opt no-new-privileges --cap-drop ALL "$image"
