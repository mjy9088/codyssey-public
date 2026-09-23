#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROOF_PATH=docs/evidence/snapshots/github-clone-pull.txt

if [ "${1:-}" != "--execute" ]; then
    echo "이 스크립트는 실제 origin/main에 증거 커밋을 push합니다." >&2
    echo "실행하려면 현재 원격의 쓰기 권한을 확인한 뒤 --execute를 지정하세요." >&2
    exit 2
fi

cd "$PROJECT_ROOT"
test "$(git branch --show-current)" = "main" || {
    echo "main 브랜치에서 실행해야 합니다." >&2
    exit 1
}
test -z "$(git status --porcelain)" || {
    echo "작업 트리가 깨끗해야 합니다." >&2
    exit 1
}

ORIGIN_URL=$(git remote get-url origin)
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || {
    echo "로컬 main과 origin/main을 먼저 동일하게 맞춰주세요." >&2
    exit 1
}

PRACTICE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/quiz-github-practice.XXXXXX")
cleanup() {
    rm -rf "$PRACTICE_ROOT"
}
trap cleanup EXIT INT TERM

echo "[1/4] 실제 GitHub origin을 별도 디렉터리에 clone합니다."
git clone --quiet "$ORIGIN_URL" "$PRACTICE_ROOT/cloned"

echo "[2/4] clone한 저장소에서 증거 파일을 commit하고 push합니다."
cd "$PRACTICE_ROOT/cloned"
git config user.name "Codyssey Git Practice"
git config user.email "practice@example.invalid"
mkdir -p "$(dirname "$PROOF_PATH")"
CLONED_FROM=$(git rev-parse HEAD)
printf 'remote=%s\ncloned_from=%s\noperation=clone -> commit -> push -> pull\n' \
    "$ORIGIN_URL" "$CLONED_FROM" > "$PROOF_PATH"
git add "$PROOF_PATH"
git commit --quiet -m "Docs: 실제 GitHub clone pull 실습 증거 갱신"
PRACTICE_COMMIT=$(git rev-parse HEAD)
git push --quiet origin main

echo "[3/4] 기존 작업 디렉터리에서 실제 origin/main을 pull합니다."
cd "$PROJECT_ROOT"
git pull --ff-only origin main

echo "[4/4] clone에서 만든 커밋과 파일이 반영됐는지 확인합니다."
test "$(git rev-parse HEAD)" = "$PRACTICE_COMMIT"
test -f "$PROOF_PATH"
grep -F "remote=$ORIGIN_URL" "$PROOF_PATH" >/dev/null
git log -2 --oneline --decorate
echo "PASS: 실제 GitHub 저장소에서 clone → commit → push → pull을 완료했습니다."
