# JSON 데이터 형식

## 파일 역할

- `quiz_game/src/quiz_game/data/initial_state.json`: 기본 퀴즈 5개와 빈 점수를 가진 읽기 전용 초기 상태
- `state.json`: 실행 중 변경된 전체 퀴즈와 최고 점수를 저장하는 프로젝트 루트 파일
- `state.json.broken*`: 읽을 수 없는 기존 상태를 복구 전에 보존한 파일

## 스키마

```json
{
  "quizzes": [
    {
      "question": "문제",
      "choices": ["선택지 1", "선택지 2", "선택지 3", "선택지 4"],
      "answer": 1
    }
  ],
  "best_score": {
    "correct": 1,
    "total": 1
  }
}
```

제약:

- `question`은 비어 있지 않은 문자열입니다.
- `choices`는 비어 있지 않은 문자열 4개를 갖습니다.
- `answer`는 `1`부터 `4` 사이의 정수입니다.
- `best_score`는 기록이 없으면 `null`입니다.
- `correct`와 `total`은 `0 <= correct <= total`을 만족하는 정수입니다.

정답률은 파생 값이므로 파일에 저장하지 않습니다. 저장은 같은 디렉터리의 임시 파일을 완성한 뒤 `state.json`으로 교체하는 방식으로 수행합니다.
