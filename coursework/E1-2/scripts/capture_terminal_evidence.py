#!/usr/bin/env python3

import argparse
import codecs
import errno
import fcntl
import hashlib
import io
import json
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path
from termios import TIOCSWINSZ


PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = PROJECT_ROOT / "docs" / "evidence" / "snapshots"
SCRIPTED_DIALOGUE = (
    ("선택: ", "2"),
    ("문제: ", "증거용으로 추가한 문제는?"),
    ("선택지 1: ", "첫 번째 선택지"),
    ("선택지 2: ", "두 번째 선택지"),
    ("선택지 3: ", "세 번째 선택지"),
    ("선택지 4: ", "네 번째 선택지"),
    ("정답 번호: ", "1"),
    ("선택: ", "3"),
    ("선택: ", "1"),
    ("정답: ", "2"),
    ("정답: ", "3"),
    ("정답: ", "4"),
    ("정답: ", "3"),
    ("정답: ", "1"),
    ("정답: ", "1"),
    ("선택: ", "4"),
    ("선택: ", "5"),
)
SCENARIO_NAMES = ("add-quiz", "quiz-list", "play-quiz", "best-score", "exit")


def run_text(*command: str) -> str:
    completed = subprocess.run(
        command,
        cwd=PROJECT_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return completed.stdout


ANSI_ESCAPE = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))")


def plain_transcript(output: str) -> str:
    """PTY 출력을 diff와 후속 렌더링에 적합한 고정 텍스트로 만든다."""
    normalized = output.replace("\r\n", "\n").replace("\r", "\n")
    return "$ python -m quiz_game\n" + ANSI_ESCAPE.sub("", normalized).rstrip() + "\n"


def split_menu_sessions(transcript: str) -> dict[str, str]:
    """한 PTY 기록을 입력과 결과가 이어진 메뉴 선택 단위로 나눈다."""
    command, separator, body = transcript.partition("\n")
    if not separator:
        raise ValueError("실행 명령 다음에 터미널 출력이 없습니다.")
    marker = "=== Python 퀴즈 ==="
    sessions = [marker + part for part in body.split(marker)[1:]]
    if len(sessions) != len(SCENARIO_NAMES):
        raise ValueError(
            f"예상한 메뉴 세션은 {len(SCENARIO_NAMES)}개지만 {len(sessions)}개입니다."
        )
    return {
        name: f"{command}\n\n{session.strip()}\n"
        for name, session in zip(SCENARIO_NAMES, sessions)
    }


def extract_revision(revision: str, destination: Path) -> None:
    archive = subprocess.run(
        ["git", "archive", "--format=tar", revision],
        cwd=PROJECT_ROOT,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as archive_file:
        archive_file.extractall(destination, filter="data")


def capture_quiz_session(destination: Path, source: Path = PROJECT_ROOT) -> str:
    with tempfile.TemporaryDirectory(prefix="quiz-evidence-") as directory:
        working_directory = Path(directory)
        # 실제 state.json을 건드리지 않도록 패키지를 임시 디렉터리에 복사한다.
        shutil.copytree(
            source / "quiz_game" / "src" / "quiz_game",
            working_directory / "quiz_game",
        )

        master_fd, slave_fd = pty.openpty()
        fcntl.ioctl(master_fd, TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        started_at = time.monotonic()
        process = subprocess.Popen(
            [sys.executable, "-m", "quiz_game"],
            cwd=working_directory,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            env={
                **os.environ,
                "TERM": "xterm-256color",
                "PYTHONUNBUFFERED": "1",
                "PYTHONPATH": str(working_directory),
            },
        )
        os.close(slave_fd)
        dialogue = iter(SCRIPTED_DIALOGUE)
        expected_prompt, response = next(dialogue)
        pending_output = ""
        # PTY는 한글 한 글자의 UTF-8 바이트를 여러 번에 나눠 반환할 수 있다.
        decoder = codecs.getincrementaldecoder("utf-8")()
        captured_output: list[str] = []

        header = {
            "version": 2,
            "width": 100,
            "height": 30,
            "timestamp": int(time.time()),
            "env": {"SHELL": "/bin/sh", "TERM": "xterm-256color"},
            "command": "python -m quiz_game",
        }
        with destination.open("w", encoding="utf-8") as output:
            output.write(json.dumps(header, ensure_ascii=False) + "\n")
            while True:
                readable, _, _ = select.select([master_fd], [], [], 0.1)
                if readable:
                    try:
                        data = os.read(master_fd, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not data:
                        break
                    decoded = decoder.decode(data)
                    if not decoded:
                        continue
                    captured_output.append(decoded)
                    pending_output += decoded
                    event = [round(time.monotonic() - started_at, 6), "o", decoded]
                    output.write(json.dumps(event, ensure_ascii=False) + "\n")
                    # 프롬프트를 확인한 뒤 답해 실제 사용자 입력 순서를 재현한다.
                    if expected_prompt and expected_prompt in pending_output:
                        os.write(master_fd, f"{response}\n".encode("utf-8"))
                        pending_output = ""
                        try:
                            expected_prompt, response = next(dialogue)
                        except StopIteration:
                            expected_prompt, response = "", ""
                elif process.poll() is not None:
                    break
        os.close(master_fd)
        if process.wait() != 0:
            raise RuntimeError("퀴즈 증거 세션 실행에 실패했습니다.")
        if expected_prompt:
            raise RuntimeError(f"예상한 프롬프트를 찾지 못했습니다: {expected_prompt}")
        return plain_transcript("".join(captured_output))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--revision",
        default="HEAD",
        help="퀴즈 실행과 Git 그래프를 생성할 Git tag 또는 commit (기본값: HEAD)",
    )
    args = parser.parse_args()
    revision = run_text("git", "rev-parse", f"{args.revision}^{{commit}}").strip()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    environment_path = OUTPUT_DIR / "environment.txt"
    graph_path = OUTPUT_DIR / "git-graph.txt"
    session_path = OUTPUT_DIR / "quiz-session.cast"
    transcript_path = OUTPUT_DIR / "quiz-session.txt"

    environment_path.write_text(
        "$ python --version\n"
        + run_text(sys.executable, "--version")
        + "\n$ git --version\n"
        + run_text("git", "--version")
        + "\n$ uname -a\n"
        + run_text("uname", "-a"),
        encoding="utf-8",
    )
    graph = run_text(
        "git", "log", "--oneline", "--graph", "--decorate", "--max-count=40", revision
    )
    graph_path.write_text(
        "$ git log --oneline --graph --decorate --all\n"
        + "\n".join(line.rstrip() for line in graph.splitlines())
        + "\n",
        encoding="utf-8",
    )
    with tempfile.TemporaryDirectory(prefix="quiz-revision-") as directory:
        source = Path(directory)
        extract_revision(revision, source)
        transcript_path.write_text(
            capture_quiz_session(session_path, source),
            encoding="utf-8",
        )
    scenario_paths: list[Path] = []
    for name, transcript in split_menu_sessions(
        transcript_path.read_text(encoding="utf-8")
    ).items():
        path = OUTPUT_DIR / f"quiz-{name}.txt"
        path.write_text(transcript, encoding="utf-8")
        scenario_paths.append(path)

    files = [
        environment_path,
        graph_path,
        session_path,
        transcript_path,
        *scenario_paths,
    ]
    manifest = {
        "revision": revision,
        "revision_input": args.revision,
        "generator": str(Path(__file__).relative_to(PROJECT_ROOT)),
        "files": {
            str(path.relative_to(PROJECT_ROOT)): {"sha256": sha256(path)} for path in files
        },
    }
    (OUTPUT_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"PASS: 터미널 증거와 해시 매니페스트를 {OUTPUT_DIR}에 생성했습니다.")


if __name__ == "__main__":
    main()
