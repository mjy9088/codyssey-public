#!/bin/bash
set -euo pipefail
node --test /app/tests/text-utils.test.mjs
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
export GIT_AUTHOR_NAME='Synthetic fixture' GIT_COMMITTER_NAME='Synthetic fixture'
export GIT_AUTHOR_EMAIL='fixture@example.invalid' GIT_COMMITTER_EMAIL='fixture@example.invalid'
export GIT_AUTHOR_DATE='2026-01-01T00:00:00+0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00+0000'
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git_lab() { GIT_MASTER=1 git -c credential.helper= -C "$temp/repo" "$@"; }
GIT_MASTER=1 git init -b main "$temp/repo" >/dev/null
printf 'base\n' > "$temp/repo/shared.txt"
git_lab add shared.txt
git_lab commit -m 'Create synthetic starting point' >/dev/null
git_lab branch feature/alpha
git_lab switch -c feature/beta >/dev/null
printf 'beta\n' > "$temp/repo/shared.txt"
git_lab commit -am 'Choose beta wording' >/dev/null
git_lab switch feature/alpha >/dev/null
printf 'alpha\n' > "$temp/repo/shared.txt"
git_lab commit -am 'Choose alpha wording' >/dev/null
if git_lab merge feature/beta --no-edit; then
  printf 'Expected a same-hunk conflict\n' >&2; exit 1
fi
test -n "$(git_lab ls-files -u)"
printf 'alpha\nbeta\n' > "$temp/repo/shared.txt"
git_lab add shared.txt
git_lab commit -m 'Preserve both independently useful lines' >/dev/null
base=$(git_lab rev-parse HEAD)
git_lab switch -c feature/remove >/dev/null
git_lab rm shared.txt >/dev/null
git_lab commit -m 'Remove synthetic shared document' >/dev/null
git_lab switch -c feature/revise "$base" >/dev/null
printf 'revised content\n' > "$temp/repo/shared.txt"
git_lab commit -am 'Revise synthetic shared document' >/dev/null
if git_lab merge feature/remove --no-edit; then
  printf 'Expected a modify/delete conflict\n' >&2; exit 1
fi
test -n "$(git_lab ls-files -u)"
git_lab add shared.txt
git_lab commit -m 'Retain revised document after conflict review' >/dev/null
tree=$(git_lab rev-parse 'HEAD^{tree}')
git_lab commit --amend -m 'Explain why the revised document remains' >/dev/null
test "$(git_lab rev-parse 'HEAD^{tree}')" = "$tree"
printf 'temporary value\n' > "$temp/repo/scratch.txt"
git_lab add scratch.txt
git_lab commit -m 'Add a local synthetic draft' >/dev/null
git_lab reset --soft HEAD~1
if git_lab diff --cached --quiet; then printf 'Soft reset lost staged changes\n' >&2; exit 1; fi
git_lab commit -m 'Record the reviewed synthetic draft' >/dev/null
GIT_MASTER=1 git init --bare -b main "$temp/remote.git" >/dev/null
git_lab remote add origin "$temp/remote.git"
git_lab push origin HEAD:main >/dev/null
published=$(git_lab rev-parse HEAD)
git_lab revert --no-edit HEAD >/dev/null
git_lab merge-base --is-ancestor "$published" HEAD
test ! -e "$temp/repo/scratch.txt"
git_lab push origin HEAD:main >/dev/null
printf 'draft in progress\n' >> "$temp/repo/shared.txt"
git_lab stash push -m 'Synthetic suspended work' >/dev/null
git_lab diff --exit-code --quiet
git_lab stash pop >/dev/null
grep -q 'draft in progress' "$temp/repo/shared.txt"
printf 'PASS: utility tests, two real conflict resolutions, amend, soft reset, revert and stash\n'
printf 'LIMIT: all Git actors/remotes are local synthetic fixtures, not human GitHub collaboration\n'
