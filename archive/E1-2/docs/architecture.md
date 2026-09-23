# 설계와 책임 분리

```text
main.py
└── quiz_game.__main__
    ├── ConsoleUI
    ├── QuizGame
    │   ├── GameState
    │   └── QuizSession → Quiz, ScoreRecord
    └── storage
```

프로그램은 다음 순서로 동작합니다.

```text
state.json 읽기
→ 없으면 initial_state.json 읽기
→ 메뉴에서 사용자 입력 받기
→ QuizGame이 상태 변경
→ 변경된 GameState를 state.json에 저장
```

- `Quiz`는 문제 데이터 검증과 정답 판정을 담당합니다.
- `QuizSession`은 한 번의 풀이 순서, 답안과 결과를 관리합니다.
- `ScoreRecord`는 정답률 우선의 최고 점수 비교 정책을 가집니다.
- `QuizGame`은 퀴즈 추가, 세션 생성, 최고 점수와 미저장 변경을 관리합니다.
- `ConsoleUI`는 입력 형식 검증과 화면 출력만 담당합니다.
- `storage`는 경로와 JSON 파일 입출력을 담당합니다.

모델의 `to_data()`와 `from_data()`는 JSON 파일에 직접 접근하지 않고 문자열, 숫자, 목록과 객체처럼 직렬화 가능한 데이터만 변환합니다. 따라서 게임 규칙과 저장 매체가 직접 결합되지 않습니다.

패키지는 `quiz_game/src/quiz_game`에 있고 테스트는 같은 컴포넌트의 `quiz_game/tests`에 둡니다. 루트 `main.py`는 과제에서 요구하는 실행 명령을 유지하기 위한 얇은 진입점입니다.
