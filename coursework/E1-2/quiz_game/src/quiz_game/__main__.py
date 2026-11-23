from pathlib import Path

from .console import ConsoleUI
from .game import QuizGame
from .storage import (
    InvalidStateError,
    StateAccessError,
    StateSaveError,
    load_state,
    preserve_invalid_file,
    save_state,
)


def persist_game(
    game: QuizGame,
    state_path: Path,
    ui: ConsoleUI,
) -> bool:
    try:
        save_state(state_path, game.export_state())
    except StateSaveError as error:
        ui.show_message(f"{error} 변경 내용은 현재 실행 중에만 유지됩니다.")
        return False
    game.mark_saved()
    return True


def play_quiz(game: QuizGame, ui: ConsoleUI, state_path: Path) -> None:
    session = game.start_quiz()
    if session is None:
        ui.show_message("등록된 퀴즈가 없습니다.")
        return

    while not session.is_finished:
        quiz = session.current_quiz
        # 반복 조건상 세션이 끝나지 않았으므로 현재 문제는 반드시 존재한다.
        assert quiz is not None
        choice = ui.ask_answer(quiz, session.current_number, session.total)
        ui.show_message("정답입니다!" if session.submit_answer(choice) else "오답입니다.")
        ui.show_live_score(session.correct_count, session.answered_count, session.total)

    result, is_new_best = game.complete_quiz(session)
    if is_new_best:
        persist_game(game, state_path, ui)
    ui.show_result(result, is_new_best)


def run_menu(
    game: QuizGame,
    ui: ConsoleUI,
    state_path: Path,
) -> None:
    while True:
        ui.show_menu()
        choice = ui.ask_menu_choice()

        if choice == 1:
            play_quiz(game, ui, state_path)
        elif choice == 2:
            game.add_quiz(ui.ask_new_quiz())
            if persist_game(game, state_path, ui):
                ui.show_message("퀴즈가 저장되었습니다.")
        elif choice == 3:
            ui.show_quizzes(game.list_quizzes())
        elif choice == 4:
            ui.show_best_score(game.get_best_score())
        else:
            return


def main() -> None:
    ui = ConsoleUI()
    # 과제 실행 위치(프로젝트 루트)에 사용자 상태를 저장한다.
    working_directory = Path.cwd()
    state_path = working_directory / "state.json"
    # 초기 문제는 설치 위치와 관계없이 패키지에 포함된 파일에서 읽는다.
    initial_state_path = Path(__file__).with_name("data") / "initial_state.json"
    try:
        state = load_state(state_path)
    except InvalidStateError as error:
        ui.show_message(str(error))
        try:
            backup_path = preserve_invalid_file(state_path)
        except StateAccessError as backup_error:
            ui.show_message(str(backup_error))
            return
        ui.show_message(f"기존 파일을 {backup_path.name}에 보존하고 기본 데이터로 시작합니다.")
        state = None
    except StateAccessError as error:
        ui.show_message(str(error))
        return

    if state is None:
        try:
            state = load_state(initial_state_path)
        except (InvalidStateError, StateAccessError) as error:
            ui.show_message(f"초기 데이터를 불러올 수 없습니다: {error}")
            return
        if state is None:
            ui.show_message("초기 데이터 파일이 없습니다.")
            return

    game = QuizGame(state)
    try:
        run_menu(game, ui, state_path)
    except (KeyboardInterrupt, EOFError):
        ui.show_message("\n입력이 중단되어 종료합니다.")
    finally:
        # 앞선 저장이 실패했을 때만 종료 직전에 한 번 더 시도한다.
        if game.has_unsaved_changes:
            ui.show_message("저장하지 못한 변경을 다시 저장합니다.")
            persist_game(game, state_path, ui)


if __name__ == "__main__":
    main()
