#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TAG_NAME=${1:-}
CONFIRM=${2:-}

if [ -z "$TAG_NAME" ] || [ "$CONFIRM" != "--execute" ]; then
    echo "사용법: sh scripts/create_submission_tag.sh TAG --execute" >&2
    echo "검증 후 annotated tag를 만들고 실제 origin에 push합니다." >&2
    exit 2
fi

cd "$PROJECT_ROOT"
test "$(git branch --show-current)" = "main" || {
    echo "FAIL: main 브랜치에서 실행해야 합니다." >&2
    exit 1
}
test -z "$(git status --porcelain)" || {
    echo "FAIL: 작업 트리가 깨끗해야 합니다." >&2
    exit 1
}
git check-ref-format "refs/tags/$TAG_NAME" >/dev/null
if git rev-parse --verify --quiet "refs/tags/$TAG_NAME" >/dev/null; then
    echo "FAIL: tag가 이미 존재합니다: $TAG_NAME" >&2
    exit 1
fi

git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || {
    echo "FAIL: 로컬 main과 origin/main이 같아야 합니다." >&2
    exit 1
}

ORIGIN_URL=$(git remote get-url origin)
PROOF_PATH=docs/evidence/snapshots/github-clone-pull.txt
test -f "$PROOF_PATH" || {
    echo "FAIL: 먼저 실제 GitHub clone/pull 실습을 완료해야 합니다." >&2
    exit 1
}
grep -F "remote=$ORIGIN_URL" "$PROOF_PATH" >/dev/null || {
    echo "FAIL: clone/pull 증거의 remote가 현재 origin과 다릅니다." >&2
    exit 1
}

sh scripts/setup_venv.sh
.venv/bin/python -m unittest discover -s quiz_game/tests -v
sh scripts/verify_public_origin.sh

git tag -a "$TAG_NAME" -m "Submission validation target: $TAG_NAME"
git push origin "refs/tags/$TAG_NAME"
echo "PASS: annotated tag $TAG_NAME 생성과 push를 완료했습니다."
