from .models import GameState, Quiz, QuizSession, ScoreRecord


class QuizGame:
    """게임 기능을 제공하고 저장이 필요한 변경을 추적한다."""

    def __init__(self, state: GameState) -> None:
        self._state = state
        self._has_unsaved_changes = False

    def start_quiz(self) -> QuizSession | None:
        if not self._state.quizzes:
            return None
        return QuizSession(self._state.quizzes)

    def complete_quiz(self, session: QuizSession) -> tuple[ScoreRecord, bool]:
        result = session.result()
        is_new_best = result.is_better_than(self._state.best_score)
        if is_new_best:
            self._state.best_score = result
            self._has_unsaved_changes = True
        return result, is_new_best

    def add_quiz(self, quiz: Quiz) -> None:
        self._state.quizzes.append(quiz)
        self._has_unsaved_changes = True

    def list_quizzes(self) -> tuple[Quiz, ...]:
        return tuple(self._state.quizzes)

    def get_best_score(self) -> ScoreRecord | None:
        return self._state.best_score

    def export_state(self) -> GameState:
        """저장 코드가 내부 퀴즈 목록을 직접 수정하지 못하도록 복사해 반환한다."""

        return GameState(list(self._state.quizzes), self._state.best_score)

    @property
    def has_unsaved_changes(self) -> bool:
        return self._has_unsaved_changes

    def mark_saved(self) -> None:
        self._has_unsaved_changes = False
