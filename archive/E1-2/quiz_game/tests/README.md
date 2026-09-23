# Tests

테스트는 실행 코드의 책임에 맞춰 나뉩니다.

- `test_models.py`: 입력 데이터 검증, 정답과 점수 비교, 직렬화
- `test_game.py`: 퀴즈 한 판의 진행과 최고 점수 갱신
- `test_storage.py`: UTF-8 JSON 저장, 손상 데이터와 백업
- `test_console.py`: 빈 입력, 잘못된 숫자와 재입력

프로젝트 루트에서 가상환경을 준비하고 실행합니다.

```bash
sh scripts/setup_venv.sh
.venv/bin/python -m unittest discover -s quiz_game/tests -v
```

테스트 이름은 `test_기대하는_동작` 형태로 읽을 수 있게 작성합니다. 파일 테스트는 `TemporaryDirectory`를 사용하므로 실제 `state.json`을 변경하지 않습니다. 콘솔 테스트는 `unittest.mock`으로 `input()`과 표준 출력을 바꿔 실제 키보드 입력 없이 재입력 흐름을 확인합니다.
