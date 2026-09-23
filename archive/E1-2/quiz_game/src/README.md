# Source layout

`quiz_game/`은 실제 Python 패키지이고 `data/`는 패키지와 함께 배포되는 읽기 전용 초기 상태입니다.

- `models.py`: 퀴즈, 점수, 세션과 상태 규칙
- `game.py`: 게임 기능과 미저장 변경 관리
- `console.py`: 터미널 입력과 출력
- `storage.py`: JSON 파일 읽기, 쓰기와 손상 파일 보존
- `__main__.py`: 객체 조립과 메뉴 실행 흐름

게임 규칙은 `input()`, `print()`와 파일 경로에 의존하지 않으며, 모델은 JSON 모듈 대신 직렬화 가능한 데이터만 변환합니다.
