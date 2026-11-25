#!/bin/sh
set -eu

mode=${1:-docker}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

case "$mode" in
    --help)
        printf '%s\n' 'Usage: sh scripts/verify.sh docker'
        exit 0
        ;;
    docker) ;;
    *)
        printf 'Unknown mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac

image="e1-2-quiz-game-verify:$$"
container="e1-2-quiz-game-verify-$$"
cleanup() {
    docker container rm --force "$container" >/dev/null 2>&1 || true
    docker image rm --force "$image" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker version >/dev/null
docker build --file "$root/scripts/Dockerfile.verify" --tag "$image" "$root"
docker run --rm \
    --name "$container" \
    --network none \
    --read-only \
    --tmpfs /tmp:rw,nosuid,nodev,noexec \
    --user 65532:65532 \
    "$image"

printf '%s\n' 'PASS: all 35 quiz game tests passed in the isolated Docker verifier.'
