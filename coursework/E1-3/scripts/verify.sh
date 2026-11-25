#!/bin/sh
set -eu
case $#:${1:-docker} in
    0:docker|1:docker) ;;
    *) printf '%s\n' 'Usage: sh scripts/verify.sh [docker]' >&2; exit 2 ;;
esac

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image=e1-3-simulator-verify:$$
container=e1-3-simulator-verify-$$
cleanup() {
    docker container rm --force "$container" >/dev/null 2>&1 || :
    docker image rm "$image" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

docker build --network none --file "$root/verify/Dockerfile" --tag "$image" "$root"
docker run --rm --name "$container" --network none --read-only \
    --tmpfs /tmp:rw,nosuid,nodev,noexec --cap-drop ALL --security-opt no-new-privileges "$image"
