# /// script
# requires-python = ">=3.11"
# dependencies = ["typing-extensions==4.15.0"]
# ///
# ─── How to run ───
# /app/.venv/bin/python /app/verify/guest_check.py

"""Deterministic acceptance checks executed inside the QEMU guest."""

import subprocess
from datetime import UTC, datetime
from pathlib import Path

from mini_git.cli import execute
from mini_git.repository import Repository


def main() -> int:
    """Exercise graph edges and the real REPL entry point in the guest."""
    repository = Repository(lambda: datetime(2026, 1, 2, 3, 4, 5, tzinfo=UTC))
    _ = execute(repository, 'init "Ada Lovelace"')
    root = repository.commit("root")
    repository.branch("feature")
    main_tip = repository.commit("main work")
    repository.switch("feature")
    feature_tip = repository.commit("login work")
    branch_path = repository.path(main_tip.commit_id, feature_tip.commit_id)
    merged = repository.merge("main")

    assert merged.parents == (feature_tip.commit_id, main_tip.commit_id)
    assert branch_path == [
        main_tip.commit_id,
        root.commit_id,
        feature_tip.commit_id,
    ]
    assert [commit.commit_id for commit in repository.log()].index(root.commit_id) == 0
    assert repository.search_keyword("LOGIN") == [feature_tip]

    commands = 'init "Grace Hopper"\ncommit "Initial commit"\nswitch missing\nquit\n'
    result = subprocess.run(
        ["/app/.venv/bin/python", "/app/main.py"],
        cwd=Path("/app"),
        input=commands,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "Initialized repository." in result.stdout
    assert "Initial commit" in result.stdout
    assert "Unknown branch: missing" in result.stdout
    print(result.stdout, end="")
    print("\nVM-CHECK-PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
