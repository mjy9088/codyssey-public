#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  sh scripts/publish-coursework.sh [--source REVISION] SUBTREE DESTINATION [TARGET_BRANCH]

Prepare a standalone-root submission commit from a local committed revision.
The source checkout is not modified. After preparing the commit, the script asks
for confirmation on a terminal before pushing to DESTINATION.

Options:
  --source REVISION  Local committed revision to publish (default: HEAD)

Arguments:
  SUBTREE       Coursework identifier or repository-relative coursework path
  DESTINATION   Git remote URL for the submission repository
  TARGET_BRANCH Destination branch (default: main)

Examples:
  coursework_id=YOUR_COURSEWORK_ID
  destination=YOUR_SUBMISSION_REPOSITORY_URL
  sh scripts/publish-coursework.sh --source HEAD "$coursework_id" "$destination" main
EOF
}

source_revision=HEAD
case ${1-} in
  --help|-h)
    usage
    exit 0
    ;;
  --source)
    if [ "$#" -lt 2 ]; then
      printf '%s\n' 'Option --source requires a revision.' >&2
      usage >&2
      exit 2
    fi
    source_revision=$2
    shift 2
    ;;
  --*)
    printf 'Unknown option: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac

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

if ! source_commit=$(git rev-parse --verify --end-of-options "$source_revision^{commit}" 2>/dev/null); then
  printf 'Source is not a local committed revision: %s\n' "$source_revision" >&2
  exit 1
fi
if ! subtree_type=$(git cat-file -t "$source_commit:$subtree" 2>/dev/null); then
  printf '%s does not exist at %s.\n' "$subtree" "$source_commit" >&2
  exit 1
fi
if [ "$subtree_type" != tree ]; then
  printf '%s is not a directory at %s.\n' "$subtree" "$source_commit" >&2
  exit 1
fi

stage=$(mktemp -d)
worktree=$stage/worktree
payload=$stage/payload
cleanup() {
  git -C "$root" worktree remove --force "$worktree" >/dev/null 2>&1 || :
  rm -rf "$stage"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

git worktree add --detach "$worktree" "$source_commit" >/dev/null
mkdir "$payload"
mv "$worktree/$subtree" "$payload/root"

git -C "$worktree" rm -r --quiet -- .
find "$payload/root" -mindepth 1 -maxdepth 1 -exec mv {} "$worktree"/ \;
git -C "$worktree" add -A

project=${subtree##*/}
git -C "$worktree" commit --quiet \
  -m "chore(submission): publish $project at repository root"
commit=$(git -C "$worktree" rev-parse HEAD)

printf '\nPrepared submission commit %s from %s.\n' "$commit" "$source_commit"
git -C "$worktree" status --short
git -C "$worktree" show --shortstat --oneline HEAD
printf '\nSubmission root:\n'
git -C "$worktree" ls-tree --name-only HEAD

if [ ! -t 0 ]; then
  printf '\nNo interactive terminal; the destination was not changed.\n'
  exit 0
fi

printf '\nPush this commit to %s (%s)? [y/N] ' \
  "$destination" "$target_branch"
IFS= read -r answer
case $answer in
  y|Y|yes|YES|Yes) ;;
  *)
    printf 'Cancelled; the destination was not changed.\n'
    exit 0
    ;;
esac

printf '\nPushing %s to %s (%s)...\n' "$commit" "$destination" "$target_branch"
git -C "$worktree" push -- "$destination" \
  "HEAD:refs/heads/$target_branch"
printf 'Published %s to %s.\n' "$project" "$destination"
