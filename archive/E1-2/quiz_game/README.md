# Quiz game component

이 폴더에는 콘솔 퀴즈 게임의 실행 코드와 테스트가 함께 있습니다.

```text
quiz_game/
├── src/
│   ├── README.md
│   └── quiz_game/
│       ├── data/initial_state.json
│       ├── __main__.py
│       ├── console.py
│       ├── game.py
│       ├── models.py
│       └── storage.py
└── tests/
    ├── README.md
    ├── test_console.py
    ├── test_game.py
    ├── test_models.py
    └── test_storage.py
```

프로젝트 루트에서 가상환경을 준비한 뒤 실행합니다.

```bash
sh scripts/setup_venv.sh
. .venv/bin/activate
python -m quiz_game
python -m unittest discover -s quiz_game/tests -v
```

`tests`는 배포 패키지에 포함되지 않으며, `src/quiz_game`의 공개 동작과 오류 경계를 검증합니다.

각 테스트의 목적과 작성 기준은 [테스트 안내](tests/README.md)를 참고하세요.
