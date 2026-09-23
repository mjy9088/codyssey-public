from __future__ import annotations

from dataclasses import dataclass, field
from typing import Sequence


@dataclass(frozen=True)
class Quiz:
    """문제 하나와 정답 판정 규칙을 나타낸다."""

    question: str
    choices: tuple[str, ...]
    answer: int

    def __post_init__(self) -> None:
        if not isinstance(self.question, str):
            raise TypeError("문제는 문자열이어야 합니다.")
        if not isinstance(self.choices, tuple):
            raise TypeError("선택지는 튜플이어야 합니다.")
        if any(not isinstance(choice, str) for choice in self.choices):
            raise TypeError("모든 선택지는 문자열이어야 합니다.")
        # Python에서는 bool도 int의 하위 타입이므로 True를 정답 1로 받지 않는다.
        if isinstance(self.answer, bool) or not isinstance(self.answer, int):
            raise TypeError("정답 번호는 정수여야 합니다.")
        if not self.question.strip():
            raise ValueError("문제는 비어 있을 수 없습니다.")
        if len(self.choices) != 4:
            raise ValueError("선택지는 정확히 4개여야 합니다.")
        if any(not choice.strip() for choice in self.choices):
            raise ValueError("선택지는 비어 있을 수 없습니다.")
        if not 1 <= self.answer <= len(self.choices):
            raise ValueError("정답 번호가 선택지 범위를 벗어났습니다.")

    def check_answer(self, choice: int) -> bool:
        return choice == self.answer

    def to_data(self) -> dict[str, object]:
        """파일 형식과 무관한 직렬화 가능 데이터로 변환한다."""

        return {
            "question": self.question,
            "choices": list(self.choices),
            "answer": self.answer,
        }

    @classmethod
    def from_data(cls, data: object) -> Quiz:
        """JSON 등에서 읽은 불투명한 데이터를 검증해 Quiz로 만든다."""

        if not isinstance(data, dict):
            raise TypeError("퀴즈는 객체여야 합니다.")
        question = data["question"]
        choices = data["choices"]
        answer = data["answer"]
        if not isinstance(choices, list):
            raise TypeError("선택지는 배열이어야 합니다.")
        return cls(question=question, choices=tuple(choices), answer=answer)


@dataclass(frozen=True)
class ScoreRecord:
    """한 번의 게임 결과와 최고 점수 비교 규칙을 나타낸다."""

    correct: int
    total: int

    def __post_init__(self) -> None:
        if (
            isinstance(self.correct, bool)
            or not isinstance(self.correct, int)
            or isinstance(self.total, bool)
            or not isinstance(self.total, int)
        ):
            raise TypeError("점수는 정수여야 합니다.")
        if self.total < 0 or not 0 <= self.correct <= self.total:
            raise ValueError("올바르지 않은 점수입니다.")

    @property
    def percentage(self) -> float:
        return self.correct / self.total * 100 if self.total else 0.0

    def is_better_than(self, other: ScoreRecord | None) -> bool:
        if other is None:
            return True
        # 나눗셈 대신 교차 곱을 쓰면 1/3 같은 정답률도 반올림 오차 없이 비교된다.
        rate_comparison = self.correct * other.total - other.correct * self.total
        if rate_comparison != 0:
            return rate_comparison > 0
        return self.correct > other.correct

    def to_data(self) -> dict[str, int]:
        return {"correct": self.correct, "total": self.total}

    @classmethod
    def from_data(cls, data: object) -> ScoreRecord:
        if not isinstance(data, dict):
            raise TypeError("점수는 객체여야 합니다.")
        return cls(correct=data["correct"], total=data["total"])


@dataclass
class GameState:
    """프로그램을 종료한 뒤에도 보존할 데이터를 한곳에 묶는다."""

    quizzes: list[Quiz] = field(default_factory=list)
    best_score: ScoreRecord | None = None

    def to_data(self) -> dict[str, object]:
        return {
            "quizzes": [quiz.to_data() for quiz in self.quizzes],
            "best_score": None if self.best_score is None else self.best_score.to_data(),
        }

    @classmethod
    def from_data(cls, data: object) -> GameState:
        if not isinstance(data, dict) or not isinstance(data.get("quizzes"), list):
            raise TypeError("게임 상태는 quizzes 배열을 포함한 객체여야 합니다.")
        score_data = data.get("best_score")
        return cls(
            quizzes=[Quiz.from_data(item) for item in data["quizzes"]],
            best_score=None if score_data is None else ScoreRecord.from_data(score_data),
        )


class QuizSession:
    """퀴즈 한 판의 현재 문제, 답안과 완료 여부를 관리한다."""

    def __init__(self, quizzes: Sequence[Quiz]) -> None:
        if not quizzes:
            raise ValueError("퀴즈가 한 개 이상 필요합니다.")
        self._quizzes = tuple(quizzes)
        self._answers: list[int] = []

    @property
    def current_quiz(self) -> Quiz | None:
        if self.is_finished:
            return None
        return self._quizzes[len(self._answers)]

    @property
    def current_number(self) -> int:
        return len(self._answers) + 1

    @property
    def total(self) -> int:
        return len(self._quizzes)

    @property
    def answered_count(self) -> int:
        return len(self._answers)

    @property
    def correct_count(self) -> int:
        return sum(
            quiz.check_answer(answer)
            for quiz, answer in zip(self._quizzes, self._answers)
        )

    @property
    def is_finished(self) -> bool:
        return len(self._answers) == len(self._quizzes)

    def submit_answer(self, choice: int) -> bool:
        quiz = self.current_quiz
        if quiz is None:
            raise RuntimeError("이미 종료된 퀴즈입니다.")
        if not 1 <= choice <= len(quiz.choices):
            raise ValueError("답안 번호가 선택지 범위를 벗어났습니다.")

        self._answers.append(choice)
        return quiz.check_answer(choice)

    def result(self) -> ScoreRecord:
        if not self.is_finished:
            raise RuntimeError("아직 퀴즈가 끝나지 않았습니다.")
        return ScoreRecord(correct=self.correct_count, total=self.total)
