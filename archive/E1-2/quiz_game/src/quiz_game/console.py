from collections.abc import Sequence

from .models import Quiz, ScoreRecord


class ConsoleUI:
    def show_menu(self) -> None:
        print("\n=== Python 퀴즈 ===")
        print("1. 퀴즈 풀기")
        print("2. 퀴즈 추가")
        print("3. 퀴즈 목록")
        print("4. 최고 점수")
        print("5. 종료")

    def ask_menu_choice(self) -> int:
        return self._ask_number("선택: ", 1, 5)

    def ask_answer(self, quiz: Quiz, number: int, total: int) -> int:
        print(f"\n진행: {number}/{total}")
        print(f"문제: {quiz.question}")
        for index, choice in enumerate(quiz.choices, start=1):
            print(f"  {index}. {choice}")
        return self._ask_number("정답: ", 1, len(quiz.choices))

    def ask_new_quiz(self) -> Quiz:
        print("\n새 퀴즈를 추가합니다.")
        question = self._ask_text("문제: ")
        choices = tuple(self._ask_text(f"선택지 {number}: ") for number in range(1, 5))
        answer = self._ask_number("정답 번호: ", 1, 4)
        return Quiz(question, choices, answer)

    def show_quizzes(self, quizzes: Sequence[Quiz]) -> None:
        if not quizzes:
            print("등록된 퀴즈가 없습니다.")
            return
        for index, quiz in enumerate(quizzes, start=1):
            print(f"{index}. {quiz.question}")

    def show_result(self, result: ScoreRecord, is_new_best: bool) -> None:
        print(
            f"결과: {result.total}문제 중 {result.correct}문제 정답 "
            f"({result.percentage:.0f}점)"
        )
        if is_new_best:
            print("새로운 최고 점수입니다!")

    def show_live_score(self, correct: int, answered: int, total: int) -> None:
        print(f"현재 점수: {correct}/{answered} | 진행: {answered}/{total}")

    def show_best_score(self, score: ScoreRecord | None) -> None:
        if score is None:
            print("아직 기록된 점수가 없습니다.")
            return
        print(f"최고 점수: {score.correct}/{score.total} ({score.percentage:.0f}점)")

    @staticmethod
    def show_message(message: str) -> None:
        print(message)

    @staticmethod
    def _ask_text(prompt: str) -> str:
        while True:
            value = input(prompt).strip()
            if value:
                return value
            print("빈 값은 입력할 수 없습니다.")

    @staticmethod
    def _ask_number(prompt: str, minimum: int, maximum: int) -> int:
        while True:
            value = input(prompt).strip()
            if not value:
                print("값을 입력해주세요.")
                continue
            try:
                number = int(value)
            except ValueError:
                print("숫자를 입력해주세요.")
                continue
            if minimum <= number <= maximum:
                return number
            print(f"{minimum}~{maximum} 사이의 숫자를 입력해주세요.")
