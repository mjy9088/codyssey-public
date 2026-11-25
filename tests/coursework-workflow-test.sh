#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export GIT_MASTER=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$tmp/repo/scripts" "$tmp/repo/coursework/B2-1"
cp "$root/scripts/coursework.sh" "$root/scripts/publish-coursework.sh" "$tmp/repo/scripts/"
cp -R "$root/coursework-tools" "$tmp/repo/"
cp "$root/.gitignore" "$tmp/repo/"
cd "$tmp/repo"
git init -q
course=coursework/B2-1
printf '%s\n' 'demo:' '    @cat example.txt' >"$course/workflow.just"
printf '%s\n' 'tracked-public-input' >"$course/example.txt"
git add .
git commit -qm source
source=$(git rev-parse HEAD)

# Local materialization updates its own files but must not take over user files.
printf '%s\n' 'user-owned' >"$course/mise.toml"
if sh scripts/coursework.sh materialize B2-1; then exit 1; fi
test "$(cat "$course/mise.toml")" = user-owned
rm "$course/mise.toml"
printf '%s\n' 'local-only' >"$course/local.txt"
sh scripts/coursework.sh materialize B2-1
cp "$course/.coursework-dev/Dockerfile.dockerignore" "$tmp/context"
sh scripts/coursework.sh materialize B2-1
cmp "$tmp/context" "$course/.coursework-dev/Dockerfile.dockerignore"
git check-ignore -q "$course/justfile"
if grep -q '^!local.txt$' "$tmp/context"; then exit 1; fi

# A dirty checkout or newer template must not affect an explicitly selected revision.
printf '%s\n' 'newer-template' >>coursework-tools/justfile
printf '%s\n' 'newer-public-input' >"$course/example.txt"
git add coursework-tools "$course/example.txt"
git commit -qm newer
head=$(git rev-parse HEAD)
out=$(sh scripts/publish-coursework.sh --prepare --source "$source" B2-1)
prepared=$(printf '%s\n' "$out" | awk '/^Prepared submission commit / {print $4}')
test "$(git rev-parse "$prepared^")" = "$source"
test "$(git rev-parse HEAD)" = "$head"
test "$(git worktree list --porcelain | grep -c '^worktree ')" -eq 1
mkdir "$tmp/standalone"
git archive "$prepared" >"$tmp/payload.tar"
tar -xf "$tmp/payload.tar" -C "$tmp/standalone"
cd "$tmp/standalone"
test -f .coursework-dev/Dockerfile
test -f .coursework-dev/shell.sh
test -f mise.toml
test ! -e local.txt
test ! -e scripts/coursework.sh
if grep -q 'newer-template' justfile; then exit 1; fi
cmp "$tmp/context" .coursework-dev/Dockerfile.dockerignore
if command -v just >/dev/null 2>&1; then test "$(just demo)" = tracked-public-input; fi
printf '%s\n' 'Coursework materialization and standalone submission checks passed.'
