import json
import tempfile
import unittest
from pathlib import Path

from quiz_game.models import GameState, Quiz, ScoreRecord
from quiz_game.storage import (
    InvalidStateError,
    StateSaveError,
    load_state,
    preserve_invalid_file,
    save_state,
)


class JsonStorageTest(unittest.TestCase):
    def test_reports_file_system_error_while_saving(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "missing" / "state.json"

            with self.assertRaises(StateSaveError):
                save_state(path, GameState())

    def test_returns_none_when_state_file_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"

            self.assertIsNone(load_state(path))

    def test_round_trip_preserves_utf8_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            expected = GameState(
                [Quiz("한글 문제", ("하나", "둘", "셋", "넷"), 3)],
                ScoreRecord(1, 1),
            )

            save_state(path, expected)
            actual = load_state(path)

            self.assertEqual(actual, expected)
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertNotIn("percentage", data["best_score"])

    def test_reports_broken_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            path.write_text("not json", encoding="utf-8")

            with self.assertRaises(InvalidStateError):
                load_state(path)

    def test_reports_invalid_field_types(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            path.write_text(
                json.dumps(
                    {
                        "quizzes": [
                            {
                                "question": 123,
                                "choices": ["A", "B", "C", "D"],
                                "answer": True,
                            }
                        ],
                        "best_score": None,
                    }
                ),
                encoding="utf-8",
            )

            with self.assertRaises(InvalidStateError):
                load_state(path)

    def test_preserves_invalid_file_without_overwriting_existing_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            path.write_text("broken", encoding="utf-8")
            path.with_suffix(".json.broken").write_text("older", encoding="utf-8")

            backup_path = preserve_invalid_file(path)

            self.assertEqual(backup_path.name, "state.json.broken.1")
            self.assertEqual(backup_path.read_text(encoding="utf-8"), "broken")
            self.assertFalse(path.exists())
