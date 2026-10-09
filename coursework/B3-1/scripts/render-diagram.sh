#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image="network-diagram:local"
docker build -f "$root/verify/Dockerfile.diagram" -t "$image" "$root"
container=$(docker create "$image")
trap 'docker rm "$container" >/dev/null' EXIT
docker cp "$container:/output/architecture.png" "$root/docs/architecture.png"
