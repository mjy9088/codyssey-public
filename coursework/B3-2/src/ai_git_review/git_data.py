import subprocess
from pathlib import Path

from ai_git_review.errors import GitCollectionError
from ai_git_review.models import ChangeContext


def _git(root: Path, *arguments: str) -> str:
    try:
        process = subprocess.run(
            ["git", *arguments],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GitCollectionError(detail=f"unable to run git: {error}") from error
    if process.returncode != 0:
        detail = process.stderr.strip() or "git command failed"
        raise GitCollectionError(detail=detail)
    return process.stdout


def collect_changes(root: Path) -> ChangeContext:
    """Collect status plus staged and unstaged patches without invoking a shell."""
    status = _git(root, "status", "--short", "--untracked-files=normal").rstrip()
    if not status:
        return ChangeContext(status="", diff="", files=())
    unstaged = _git(root, "diff", "--no-ext-diff", "--unified=3")
    staged = _git(root, "diff", "--cached", "--no-ext-diff", "--unified=3")
    files: list[str] = []
    for line in status.splitlines():
        path = line[3:].strip()
        if " -> " in path:
            path = path.split(" -> ", maxsplit=1)[1]
        files.append(path)
    return ChangeContext(status=status, diff=staged + unstaged, files=tuple(files))
