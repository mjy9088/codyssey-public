# 터미널 증거 생성

GUI가 필요하지 않은 제출 증거는 다음 명령으로 다시 생성할 수 있습니다.

```bash
.venv/bin/python scripts/capture_terminal_evidence.py
```

생성 결과:

- `snapshots/environment.txt`: Python, Git과 운영체제 정보
- `snapshots/git-graph.txt`: 브랜치와 병합 그래프
- `snapshots/quiz-session.cast`: 퀴즈 추가, 목록, 전체 플레이, 점수 확인과 종료를 기록한 asciinema v2 형식의 PTY 세션
- `snapshots/quiz-session.txt`: 같은 PTY 세션에서 프롬프트와 입력 echo를 포함해 추출한 고정 텍스트
- `snapshots/quiz-{add-quiz,quiz-list,play-quiz,best-score,exit}.txt`: 메뉴 선택별 연속 구간
- `snapshots/manifest.json`: 생성 기준 Git revision과 각 파일의 SHA-256

`quiz-session.txt`는 시간 정보나 터미널 제어 문자를 제외했기 때문에 diff로 검토하거나 이후 SVG 같은 제출 형식의 입력으로 사용하기 좋습니다. 입력값을 별도로 꾸며 넣지 않고 PTY의 실제 입력 echo를 보존합니다.
메뉴 선택별 파일도 결과 줄만 추리는 대신 해당 메뉴와 프롬프트부터 마지막 결과까지를 연속해서 보존합니다.

`.cast`는 JSON Lines 텍스트이므로 별도 도구 없이도 검토할 수 있습니다. asciinema가 설치된 환경에서는 다음처럼 실제 터미널 흐름으로 재생할 수도 있습니다.

```bash
asciinema play docs/evidence/snapshots/quiz-session.cast
```

브라우저 없이 제출용 SVG를 생성하려면 다음 명령을 실행합니다. SVG는 원본 텍스트와 자신의 SHA-256을 별도 매니페스트에 기록합니다.

```bash
.venv/bin/python scripts/render_terminal_svgs.py
```

SVG를 제출용 PNG로 변환할 때는 저장소의 Dockerfile로 resvg와 Noto CJK 버전을 고정합니다.

```bash
.venv/bin/python scripts/rasterize_submission_svgs.py
```
