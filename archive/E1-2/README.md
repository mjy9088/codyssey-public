# Python 퀴즈 게임

터미널에서 문제를 풀고 새로운 문제를 등록하는 Python 콘솔 게임입니다. 추가한 문제와 최고 점수는 프로젝트 루트의 `state.json`에 저장되어 다음 실행에도 유지됩니다.

## 퀴즈 주제와 선정 이유

기본 주제는 Python 기초 문법입니다. 함수, 리스트, 조건문, 딕셔너리와 JSON처럼 이 프로젝트에서 직접 사용하는 개념을 문제로 다시 확인하기에 적합해서 선정했습니다.

## 시작하기

Python 3.10 이상이 필요하며 외부 라이브러리는 사용하지 않습니다. 다음 스크립트는 프로젝트 루트에 `.venv`를 만들고 로컬 `src` 패키지를 연결합니다.

```bash
sh scripts/setup_venv.sh
. .venv/bin/activate
python main.py
```

테스트는 가상환경에서 실행합니다.

```bash
python -m unittest discover -s quiz_game/tests -v
```

가상환경을 활성화하지 않은 경우 `.venv/bin/python`을 직접 사용할 수 있습니다.

## 기능 목록

- 기본 문제와 사용자가 추가한 문제 풀기
- 문제, 선택지 4개와 정답 번호를 입력해 퀴즈 추가
- 등록된 퀴즈 목록과 최고 점수 확인
- 빈 입력, 숫자 변환 실패와 범위 오류 재입력
- UTF-8 JSON 상태 저장과 손상 파일 보존
- 입력 중단 시 안전한 종료와 미저장 데이터 저장 재시도

## 파일 구조

```text
.
├── quiz_game/
│   ├── README.md
│   ├── src/quiz_game/       # 실행 패키지와 초기 데이터
│   └── tests/               # 책임별 단위 테스트
├── scripts/                 # 환경 설정, Git 실습과 증거 생성
├── docs/                    # 설계, 데이터 형식과 제출 증거
└── main.py                  # 과제 실행 방식 호환 진입점
```

## 데이터 파일

패키지의 `data/initial_state.json`에는 기본 퀴즈 5개가 들어 있습니다. 퀴즈를 추가하거나 최고 점수가 갱신되면 기본 문제를 포함한 현재 전체 상태를 프로젝트 루트의 UTF-8 `state.json`에 저장합니다. 손상된 파일은 `state.json.broken`, `state.json.broken.1`처럼 보존합니다.

```json
{
  "quizzes": [
    {
      "question": "Python에서 함수를 정의할 때 사용하는 키워드는?",
      "choices": ["func", "def", "function", "lambda"],
      "answer": 2
    }
  ],
  "best_score": {
    "correct": 4,
    "total": 5
  }
}
```

`best_score`는 기록이 없으면 `null`입니다. 정답률은 중복 저장하지 않고 `correct`와 `total`에서 계산합니다. 자세한 제약은 [데이터 형식 문서](docs/data-format.md)를 참고하세요.

## 문서

- [퀴즈 게임 컴포넌트](quiz_game/README.md)
- [처음 보는 사람을 위한 핵심 개념](docs/concepts.md)
- [설계와 책임 분리](docs/architecture.md)
- [JSON 데이터 형식](docs/data-format.md)
- [실제 GitHub clone/pull 실습](docs/git-practice.md)
- [재현 가능한 제출 증거](docs/evidence/README.md)
- [제출 스크린샷과 관리 정책](docs/submission/README.md)
