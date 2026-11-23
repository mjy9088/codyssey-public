#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "50-git"

section "Disposable workstation Git configuration"
# .invalid 기본값은 재현 검증용이며 실제 값은 LAB_GIT_NAME/LAB_GIT_EMAIL로 주입한다.
# DinD의 root와 호스트 작업트리 소유자가 다르므로 격리된 마운트 지점만 허용한다.
git config --global --replace-all safe.directory /workspace
git config --global user.name "${LAB_GIT_NAME:?}"
git config --global user.email "${LAB_GIT_EMAIL:?}"
git config --global init.defaultBranch main

git config --global --get user.name
git config --global --get user.email
git config --global --get init.defaultBranch
git config --global --list
assert_eq "Git user.name" "${LAB_GIT_NAME:?}" \
  "$(git config --global --get user.name)"
assert_eq "Git user.email" "${LAB_GIT_EMAIL:?}" \
  "$(git config --global --get user.email)"
assert_eq "Git default branch" "main" \
  "$(git config --global --get init.defaultBranch)"

section "Repository and remote"
git status --short --branch
if git remote get-url origin >/dev/null 2>&1; then
  git remote -v
  assert_contains "origin remote" "$(git remote get-url origin)" \
    "github.com"
else
  echo "Origin remote is required." >&2
  exit 1
fi

end_validation
