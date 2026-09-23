"""GameState와 UTF-8 JSON 파일 사이의 입출력을 담당한다."""

import json
from pathlib import Path

from .models import GameState


class InvalidStateError(Exception):
    """저장 데이터의 형식이나 내용이 올바르지 않을 때 발생한다."""


class StateAccessError(Exception):
    """파일 시스템 문제로 저장 데이터에 접근하지 못할 때 발생한다."""


class StateSaveError(Exception):
    """게임 상태를 파일에 저장하지 못할 때 발생한다."""


def load_state(path: Path) -> GameState | None:
    if not path.exists():
        return None

    try:
        with path.open(encoding="utf-8") as file:
            data = json.load(file)
    except OSError as error:
        raise StateAccessError("저장 파일을 읽을 수 없습니다.") from error
    except json.JSONDecodeError as error:
        raise InvalidStateError("저장 파일의 JSON 형식이 올바르지 않습니다.") from error

    try:
        return GameState.from_data(data)
    except (KeyError, TypeError, ValueError) as error:
        raise InvalidStateError("저장 데이터의 구조가 올바르지 않습니다.") from error


def save_state(path: Path, state: GameState) -> None:
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    try:
        # 원본을 바로 쓰지 않고 완성된 임시 파일을 교체해 중간 실패에 대비한다.
        with temporary_path.open("w", encoding="utf-8") as file:
            json.dump(state.to_data(), file, ensure_ascii=False, indent=2)
            file.write("\n")
        temporary_path.replace(path)
    except OSError as error:
        raise StateSaveError("게임 상태를 저장할 수 없습니다.") from error


def preserve_invalid_file(path: Path) -> Path:
    # 이전 백업도 남기기 위해 사용하지 않은 번호를 찾는다.
    backup_path = path.with_suffix(path.suffix + ".broken")
    sequence = 1
    while backup_path.exists():
        backup_path = path.with_suffix(f"{path.suffix}.broken.{sequence}")
        sequence += 1
    try:
        path.replace(backup_path)
    except OSError as error:
        raise StateAccessError("손상된 저장 파일을 보존할 수 없습니다.") from error
    return backup_path
