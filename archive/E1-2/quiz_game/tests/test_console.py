import io
import unittest
from unittest.mock import patch

from quiz_game.console import ConsoleUI
from quiz_game.models import Quiz


class ConsoleInputTest(unittest.TestCase):
    def test_displays_question_progress(self) -> None:
        quiz = Quiz("문제", ("A", "B", "C", "D"), 1)
        output = io.StringIO()
        with (
            patch("builtins.input", return_value="1"),
            patch("sys.stdout", output),
        ):
            ConsoleUI().ask_answer(quiz, 2, 5)

        self.assertIn("진행: 2/5", output.getvalue())
        self.assertIn("문제: 문제", output.getvalue())

    def test_retries_empty_invalid_and_out_of_range_numbers(self) -> None:
        output = io.StringIO()
        with (
            patch("builtins.input", side_effect=["", "abc", "9", " 3 "]),
            patch("sys.stdout", output),
        ):
            choice = ConsoleUI().ask_menu_choice()

        self.assertEqual(choice, 3)
        self.assertIn("값을 입력해주세요.", output.getvalue())
        self.assertIn("숫자를 입력해주세요.", output.getvalue())
        self.assertIn("1~5 사이의 숫자를 입력해주세요.", output.getvalue())

    def test_retries_empty_question_while_adding_quiz(self) -> None:
        with (
            patch(
                "builtins.input",
                side_effect=["", "문제", "A", "B", "C", "D", "2"],
            ),
            patch("sys.stdout", io.StringIO()),
        ):
            quiz = ConsoleUI().ask_new_quiz()

        self.assertEqual(quiz.question, "문제")
        self.assertEqual(quiz.answer, 2)
