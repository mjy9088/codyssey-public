#!/bin/sh
set -eu
case $#:${1:-docker} in
    0:docker|1:docker) ;;
    *) printf '%s\n' 'Usage: sh scripts/verify.sh [docker]' >&2; exit 2 ;;
esac

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$stage"
# Keep the staging root private, but let the nested NGINX worker read its assets.
umask 022
export COMPOSE_PROJECT_NAME="e1-1-verify-$(basename "$stage" | tr '[:upper:].' '[:lower:]-')"
export COMPOSE_FILE=docker-compose.yml:verify-compose.yml
export LAB_GIT_NAME=workstation-student LAB_GIT_EMAIL=student@example.invalid

mkdir -p app scripts tests/expected .local/evidence/actual .local/evidence/diff "$stage/git-home"
cp "$root/.dockerignore" "$root/Dockerfile" "$root/docker-compose.yml" "$root/lab.bash" .
cp "$root/app/Dockerfile" "$root/app/index.html" app/
chmod 0644 app/index.html
for script in lib 10-cli-and-permissions 20-environment-and-docker 30-custom-image \
    40-storage 50-git 60-browser-evidence; do
    cp "$root/scripts/$script.bash" scripts/
done
cp "$root/tests/expected/browser-with-address-bar.png" tests/expected/

# The lab checks Git configuration and origin metadata, but makes no remote request.
env -i PATH="$PATH" HOME="$stage/git-home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    sh -eu -c '
        git init --quiet --template= .
        git config --local remote.origin.url https://github.com/example/workstation-lab.git
    '
cat >verify-compose.yml <<'YAML'
services:
  workstation:
    ports: !reset []
YAML

cleanup() {
    status=$?
    trap - EXIT
    if ! docker compose down --volumes --remove-orphans --rmi local; then
        printf '%s\n' "Could not remove Compose resources for $COMPOSE_PROJECT_NAME." >&2
        [ "$status" -ne 0 ] || status=1
    fi
    rm -rf "$stage"
    exit "$status"
}
docker compose config --quiet
trap cleanup EXIT
bash lab.bash run
