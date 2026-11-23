import unittest

from quiz_game.game import QuizGame
from quiz_game.models import GameState, Quiz, QuizSession, ScoreRecord


def make_quiz(answer: int = 1) -> Quiz:
    return Quiz("문제", ("A", "B", "C", "D"), answer)


class QuizSessionTest(unittest.TestCase):
    def test_finishes_and_calculates_result(self) -> None:
        session = QuizSession([make_quiz(1), make_quiz(2)])

        self.assertTrue(session.submit_answer(1))
        self.assertFalse(session.submit_answer(3))

        self.assertEqual(session.answered_count, 2)
        self.assertEqual(session.correct_count, 1)
        self.assertTrue(session.is_finished)
        self.assertEqual(session.result(), ScoreRecord(1, 2))

    def test_rejects_result_before_session_finishes(self) -> None:
        with self.assertRaises(RuntimeError):
            QuizSession([make_quiz()]).result()

    def test_rejects_answer_after_session_finishes(self) -> None:
        session = QuizSession([make_quiz()])
        session.submit_answer(1)

        with self.assertRaises(RuntimeError):
            session.submit_answer(1)


class QuizGameTest(unittest.TestCase):
    def test_returns_none_when_there_are_no_quizzes(self) -> None:
        self.assertIsNone(QuizGame(GameState()).start_quiz())

    def test_updates_best_score(self) -> None:
        game = QuizGame(GameState([make_quiz()]))
        session = game.start_quiz()
        assert session is not None
        session.submit_answer(1)

        result, updated = game.complete_quiz(session)

        self.assertTrue(updated)
        self.assertEqual(result, ScoreRecord(1, 1))
        self.assertEqual(game.export_state().best_score, result)
        self.assertTrue(game.has_unsaved_changes)

    def test_keeps_existing_best_score_when_result_is_lower(self) -> None:
        best_score = ScoreRecord(1, 1)
        game = QuizGame(GameState([make_quiz()], best_score))
        session = game.start_quiz()
        assert session is not None
        session.submit_answer(2)

        result, updated = game.complete_quiz(session)

        self.assertFalse(updated)
        self.assertEqual(result, ScoreRecord(0, 1))
        self.assertEqual(game.get_best_score(), best_score)
        self.assertFalse(game.has_unsaved_changes)

    def test_tracks_unsaved_changes_until_marked_as_saved(self) -> None:
        game = QuizGame(GameState())

        self.assertFalse(game.has_unsaved_changes)
        game.add_quiz(make_quiz())
        self.assertTrue(game.has_unsaved_changes)
        game.mark_saved()
        self.assertFalse(game.has_unsaved_changes)
