"""CLI parsing and end-to-end REPL tests."""

import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

from mini_git.cli import execute
from mini_git.repository import Repository

ROOT = Path(__file__).resolve().parents[1]


def repo() -> Repository:
    return Repository(lambda: datetime(2026, 1, 2, 3, 4, 5, tzinfo=UTC))


def test_execute_accepts_case_insensitive_commands_and_quoted_arguments() -> None:
    # Given
    repository = repo()

    # When
    initialized, _ = execute(repository, 'iNiT "Ada Lovelace"')
    committed, _ = execute(repository, 'CoMmIt "Add login flow"')
    found, _ = execute(repository, 'SeArCh "LOGIN"')

    # Then
    assert initialized.startswith("Initialized repository.")
    assert "Add login flow" in committed
    assert "Add login flow" in found


def test_execute_standardizes_invalid_and_unknown_errors() -> None:
    # Given
    repository = repo()
    _ = execute(repository, "init Ada")

    # When / Then
    assert execute(repository, "commit")[0] == "Invalid args"
    assert execute(repository, "switch missing")[0] == "Unknown branch: missing"
    assert execute(repository, "ancestors missing")[0] == "Unknown commit: missing"


def test_repl_runs_happy_and_error_paths_through_main_entrypoint() -> None:
    # Given
    commands = "\n".join(
        [
            'init "Ada Lovelace"',
            'commit "Initial commit"',
            "branch feature",
            "switch feature",
            'commit "Add login"',
            "log",
            "search login",
            "switch missing",
            "quit",
            "",
        ]
    )

    # When
    result = subprocess.run(
        [sys.executable, "main.py"],
        cwd=ROOT,
        input=commands,
        capture_output=True,
        text=True,
        check=False,
    )

    # Then
    assert result.returncode == 0
    assert result.stdout.count("mini-git> ") == 9
    assert "Initialized repository." in result.stdout
    assert "Initial commit" in result.stdout
    assert "Add login" in result.stdout
    assert "Unknown branch: missing" in result.stdout
