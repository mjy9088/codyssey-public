import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from quiz_game import __main__ as application
from quiz_game.console import ConsoleUI
from quiz_game.models import Quiz
from quiz_game.storage import StateSaveError, load_state


class ApplicationFlowTest(unittest.TestCase):
    def test_interrupted_input_retries_failed_persistence_before_exit(self) -> None:
        for interruption in (KeyboardInterrupt(), EOFError()):
            with self.subTest(interruption=type(interruption).__name__):
                with tempfile.TemporaryDirectory() as directory:
                    state_path = Path(directory) / "state.json"
                    real_save = application.save_state
                    attempts = 0

                    def fail_first_save(path, state):
                        nonlocal attempts
                        attempts += 1
                        if attempts == 1:
                            raise StateSaveError("synthetic write failure")
                        real_save(path, state)

                    output = io.StringIO()
                    inputs = ["2", "Added question", "A", "B", "C", "D", "1", interruption]
                    with (
                        patch.object(application.Path, "cwd", return_value=Path(directory)),
                        patch.object(application, "save_state", side_effect=fail_first_save),
                        patch("builtins.input", side_effect=inputs),
                        patch("sys.stdout", output),
                    ):
                        application.main()

                    state = load_state(state_path)
                    self.assertIsNotNone(state)
                    assert state is not None
                    self.assertEqual(state.quizzes[-1].question, "Added question")
                    self.assertEqual(attempts, 2)
                    self.assertIn("입력이 중단되어 종료합니다.", output.getvalue())
                    self.assertIn("저장하지 못한 변경을 다시 저장합니다.", output.getvalue())

    def test_bundled_initial_state_contains_at_least_five_valid_quizzes(self) -> None:
        path = Path(application.__file__).with_name("data") / "initial_state.json"

        state = load_state(path)

        self.assertIsNotNone(state)
        assert state is not None
        self.assertGreaterEqual(len(state.quizzes), 5)

    def test_quiz_list_renders_numbered_questions_and_empty_state(self) -> None:
        output = io.StringIO()
        ui = ConsoleUI()
        quizzes = (
            Quiz("First synthetic question", ("A", "B", "C", "D"), 1),
            Quiz("Second synthetic question", ("A", "B", "C", "D"), 2),
        )

        with patch("sys.stdout", output):
            ui.show_quizzes(quizzes)
            ui.show_quizzes(())

        rendered = output.getvalue()
        self.assertIn("1. First synthetic question", rendered)
        self.assertIn("2. Second synthetic question", rendered)
        self.assertIn("등록된 퀴즈가 없습니다.", rendered)


if __name__ == "__main__":
    unittest.main()
