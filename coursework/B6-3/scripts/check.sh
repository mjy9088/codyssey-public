#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image="folio-lending-check:local"
docker version >/dev/null
docker build --file "$root/verify/check.Dockerfile" --tag "$image" "$root"
docker run --rm --read-only --tmpfs /tmp:size=16m,mode=1777 \
  --security-opt no-new-privileges --cap-drop ALL "$image"
