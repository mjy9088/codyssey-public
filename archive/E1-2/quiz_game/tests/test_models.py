import unittest

from quiz_game.models import GameState, Quiz, ScoreRecord


class QuizTest(unittest.TestCase):
    def test_checks_answer(self) -> None:
        quiz = Quiz("정답은?", ("A", "B", "C", "D"), 2)
        self.assertTrue(quiz.check_answer(2))
        self.assertFalse(quiz.check_answer(1))

    def test_rejects_invalid_quiz(self) -> None:
        with self.assertRaises(ValueError):
            Quiz("문제", ("A", "B"), 1)

    def test_rejects_non_string_question_and_boolean_answer(self) -> None:
        with self.assertRaises(TypeError):
            Quiz(123, ("A", "B", "C", "D"), 1)  # type: ignore[arg-type]
        with self.assertRaises(TypeError):
            Quiz("문제", ("A", "B", "C", "D"), True)


class ScoreRecordTest(unittest.TestCase):
    def test_compares_accuracy_before_correct_count(self) -> None:
        self.assertTrue(ScoreRecord(1, 1).is_better_than(ScoreRecord(9, 10)))

    def test_prefers_more_correct_answers_when_accuracy_is_equal(self) -> None:
        self.assertTrue(ScoreRecord(2, 4).is_better_than(ScoreRecord(1, 2)))


class GameStateTest(unittest.TestCase):
    def test_converts_to_opaque_data_and_back(self) -> None:
        expected = GameState(
            quizzes=[Quiz("문제", ("A", "B", "C", "D"), 3)],
            best_score=ScoreRecord(1, 1),
        )

        restored = GameState.from_data(expected.to_data())

        self.assertEqual(restored, expected)
