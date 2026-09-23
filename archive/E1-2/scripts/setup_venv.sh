#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PYTHON=${PYTHON:-python3}

cd "$PROJECT_ROOT"
# 외부 패키지가 없으므로 pip 없이도 격리된 Python 실행 환경이면 충분하다.
"$PYTHON" -m venv --clear --without-pip .venv
SITE_PACKAGES=$(
    .venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])'
)
# .pth 파일은 가상환경의 import 검색 경로에 로컬 src 폴더를 추가한다.
printf '%s\n' "$PROJECT_ROOT/quiz_game/src" > "$SITE_PACKAGES/codyssey_quiz_game.pth"

printf '\n가상환경 준비가 완료되었습니다.\n'
printf '활성화: . .venv/bin/activate\n'
printf '실행:   python main.py\n'
printf '테스트: python -m unittest discover -s quiz_game/tests -v\n'
