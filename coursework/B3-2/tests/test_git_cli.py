import os
import subprocess
import tempfile
from pathlib import Path

from ai_git_review.cli import run
from ai_git_review.git_data import collect_changes


def git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True)


def git_output(cwd: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True, text=True
    ).stdout


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


def test_collect_changes_includes_staged_and_unstaged_patches() -> None:
    root = make_repo()
    (root / "app.py").write_text("print('staged')\n", encoding="utf-8")
    git(root, "add", "app.py")
    (root / "app.py").write_text("print('unstaged')\n", encoding="utf-8")

    context = collect_changes(root)

    assert context.status.startswith("MM app.py")
    assert "+print('staged')" in context.diff
    assert "+print('unstaged')" in context.diff


def test_draft_generation_does_not_mutate_reviewed_repository() -> None:
    root = make_repo()
    (root / "app.py").write_text("print('staged')\n", encoding="utf-8")
    git(root, "add", "app.py")
    (root / "app.py").write_text("print('unstaged')\n", encoding="utf-8")
    before = (
        git_output(root, "status", "--porcelain=v1"),
        git_output(root, "diff"),
        git_output(root, "diff", "--cached"),
        git_output(root, "rev-parse", "HEAD"),
        (root / "app.py").read_bytes(),
    )
    previous = Path.cwd()
    os.chdir(root)
    try:
        assert run(["commit"]) == 0
    finally:
        os.chdir(previous)

    after = (
        git_output(root, "status", "--porcelain=v1"),
        git_output(root, "diff"),
        git_output(root, "diff", "--cached"),
        git_output(root, "rev-parse", "HEAD"),
        (root / "app.py").read_bytes(),
    )
    assert after == before
