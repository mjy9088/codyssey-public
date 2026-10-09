import os
import subprocess
import tempfile
from pathlib import Path

from ai_git_review.cli import run
from ai_git_review.git_data import collect_changes


def git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True)


def make_repo() -> Path:
    root = Path(tempfile.mkdtemp(prefix="ai-review-test-"))
    git(root, "init", "-q")
    git(root, "config", "user.name", "Synthetic Tester")
    git(root, "config", "user.email", "tester.invalid@example.invalid")
    (root / "app.py").write_text("print('old')\n", encoding="utf-8")
    git(root, "add", "app.py")
    git(root, "commit", "-qm", "initial fixture")
    return root


def test_collect_changes_reads_status_and_worktree_diff() -> None:
    root = make_repo()
    (root / "app.py").write_text("print('new')\n", encoding="utf-8")

    context = collect_changes(root)

    assert "app.py" in context.status
    assert "+print('new')" in context.diff
    assert context.files == ("app.py",)


def test_cli_fixture_default_needs_no_key_or_network() -> None:
    root = make_repo()
    (root / "app.py").write_text("print('new')\n", encoding="utf-8")
    previous = Path.cwd()
    os.chdir(root)
    try:
        assert run(["commit"]) == 0
    finally:
        os.chdir(previous)


def test_cli_reports_clean_repository() -> None:
    root = make_repo()
    previous = Path.cwd()
    os.chdir(root)
    try:
        assert run(["pr"]) == 0
    finally:
        os.chdir(previous)


def test_api_backend_requires_explicit_network_opt_in() -> None:
    root = make_repo()
    (root / "app.py").write_text("print('new')\n", encoding="utf-8")
    previous = Path.cwd()
    os.chdir(root)
    try:
        assert run(["commit", "--backend", "api"]) == 2
    finally:
        os.chdir(previous)
