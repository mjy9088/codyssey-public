import unittest

from scripts.capture_terminal_evidence import plain_transcript, split_menu_sessions


class PlainTranscriptTest(unittest.TestCase):
    def test_keeps_prompts_and_echoed_input_while_normalizing_terminal_output(self) -> None:
        output = "\x1b[32m선택: \x1b[0m2\r\n문제: 예시\r\n"

        self.assertEqual(
            plain_transcript(output),
            "$ python -m quiz_game\n선택: 2\n문제: 예시\n",
        )

    def test_splits_complete_menu_sessions_without_dropping_input(self) -> None:
        menu = "=== Python 퀴즈 ===\n선택: {}\n결과 {}\n"
        transcript = "$ python -m quiz_game\n\n" + "\n".join(
            menu.format(number, number) for number in range(1, 6)
        )

        sessions = split_menu_sessions(transcript)

        self.assertEqual(
            list(sessions),
            ["add-quiz", "quiz-list", "play-quiz", "best-score", "exit"],
        )
        self.assertIn("선택: 3\n결과 3", sessions["play-quiz"])

    def test_rejects_an_incomplete_menu_session(self) -> None:
        with self.assertRaisesRegex(ValueError, "메뉴 세션"):
            split_menu_sessions("$ python -m quiz_game\n=== Python 퀴즈 ===\n선택: 1\n")


if __name__ == "__main__":
    unittest.main()
