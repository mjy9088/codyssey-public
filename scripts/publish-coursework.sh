#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-coursework.sh SUBTREE DESTINATION [TARGET_BRANCH]

Prepare a standalone-root submission commit from the latest origin/public.
The source checkout is not modified. After preparing the commit, the script asks
for confirmation on a terminal before force-pushing to DESTINATION.

Arguments:
  SUBTREE       Coursework identifier or repository-relative coursework path
  DESTINATION   Git remote URL for the submission repository
  TARGET_BRANCH Destination branch (default: main)

Examples:
  coursework_id=YOUR_COURSEWORK_ID
  destination=YOUR_SUBMISSION_REPOSITORY_URL
  scripts/publish-coursework.sh "$coursework_id" "$destination" main
EOF
}

if [ "${1-}" = --help ] || [ "${1-}" = -h ]; then
  usage
  exit 0
fi

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage >&2
  exit 2
fi

case $1 in
  coursework/*) subtree=$1 ;;
  *) subtree=coursework/$1 ;;
esac
destination=$2
target_branch=${3-main}

case $subtree in
  coursework/*) ;;
  *) printf 'Invalid coursework subtree: %s\n' "$subtree" >&2; exit 2 ;;
esac
case $subtree in
  *..*|*/.|*/../*|*/) printf 'Invalid coursework subtree: %s\n' "$subtree" >&2; exit 2 ;;
esac
if ! git check-ref-format --branch "$target_branch" >/dev/null 2>&1; then
  printf 'Invalid target branch: %s\n' "$target_branch" >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
cd "$root"

source_ref=refs/remotes/origin/public
git fetch origin "+refs/heads/public:$source_ref"
git rev-parse --verify "$source_ref^{commit}" >/dev/null
if ! git cat-file -e "$source_ref:$subtree" 2>/dev/null; then
  printf '%s does not exist at %s.\n' "$subtree" "$source_ref" >&2
  exit 1
fi

stage=$(mktemp -d)
worktree=$stage/worktree
payload=$stage/payload
cleanup() {
  git -C "$root" worktree remove --force "$worktree" >/dev/null 2>&1 || :
  rm -rf "$stage"
}
trap cleanup 0 HUP INT TERM

git worktree add --detach "$worktree" "$source_ref" >/dev/null
mkdir "$payload"
mv "$worktree/$subtree" "$payload/root"

git -C "$worktree" rm -r --quiet -- .
find "$payload/root" -mindepth 1 -maxdepth 1 -exec mv {} "$worktree"/ \;
git -C "$worktree" add -A

project=${subtree##*/}
git -C "$worktree" commit --quiet \
  -m "chore(submission): publish $project at repository root"
commit=$(git -C "$worktree" rev-parse HEAD)

printf '\nPrepared submission commit %s from %s.\n' "$commit" "$source_ref"
git -C "$worktree" status --short
git -C "$worktree" show --shortstat --oneline HEAD
printf '\nSubmission root:\n'
git -C "$worktree" ls-tree --name-only HEAD

if [ ! -t 0 ]; then
  printf '\nNo interactive terminal; the destination was not changed.\n'
  exit 0
fi

printf '\nForce-push this commit to %s (%s)? [y/N] ' \
  "$destination" "$target_branch"
IFS= read -r answer
case $answer in
  y|Y|yes|YES|Yes) ;;
  *)
    printf 'Cancelled; the destination was not changed.\n'
    exit 0
    ;;
esac

printf '\nForce-pushing %s to %s (%s)...\n' "$commit" "$destination" "$target_branch"
git -C "$worktree" push --force "$destination" \
  "HEAD:refs/heads/$target_branch"
printf 'Published %s to %s.\n' "$project" "$destination"
