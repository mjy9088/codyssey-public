"""Command parsing and REPL boundary."""

import shlex
from collections.abc import Callable
from datetime import datetime
from typing import Final, TypeAlias

from mini_git.errors import MiniGitError
from mini_git.model import Commit, CommitId
from mini_git.repository import Repository

INVALID_ARGS: Final = "Invalid args"
PATH_ARGUMENT_COUNT: Final = 2
CommandResult: TypeAlias = tuple[str, bool]
CommandHandler: TypeAlias = Callable[[Repository, list[str]], CommandResult]


def execute(repository: Repository, line: str) -> CommandResult:
    """Execute one command and return output plus continuation state."""
    try:
        parts = shlex.split(line)
    except ValueError:
        return INVALID_ARGS, True
    if not parts:
        return "", True
    command = parts[0].casefold()
    handler = _COMMANDS.get(command)
    if handler is None:
        return f"Unknown command: {parts[0]}", True
    try:
        return handler(repository, parts[1:])
    except MiniGitError as error:
        return str(error), True


def _init(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != 1:
        return INVALID_ARGS, True
    repository.initialize(arguments[0])
    return (
        f"Initialized repository.\nCurrent branch: main\nCurrent user: {arguments[0]}",
        True,
    )


def _branch(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != 1:
        return INVALID_ARGS, True
    repository.branch(arguments[0])
    return f"Created branch: {arguments[0]}", True


def _switch(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != 1:
        return INVALID_ARGS, True
    repository.switch(arguments[0])
    return f"Switched to branch: {arguments[0]}", True


def _commit(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != 1:
        return INVALID_ARGS, True
    commit = repository.commit(arguments[0])
    return f"[{commit.commit_id}] {commit.message}", True


def _merge(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != 1:
        return INVALID_ARGS, True
    commit = repository.merge(arguments[0])
    return f"[{commit.commit_id}] {commit.message}", True


def _log(repository: Repository, arguments: list[str]) -> CommandResult:
    if not arguments:
        return _format_commits(repository.log()), True
    if len(arguments) == 1 and arguments[0].casefold().startswith("--sort-by="):
        mode = arguments[0].split("=", 1)[1]
        return _format_commits(repository.log(mode)), True
    return INVALID_ARGS, True


def _path(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != PATH_ARGUMENT_COUNT:
        return INVALID_ARGS, True
    return _format_path(repository.path(arguments[0], arguments[1])), True


def _ancestors(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != 1:
        return INVALID_ARGS, True
    return _format_commits(repository.ancestors(arguments[0])), True


def _search(repository: Repository, arguments: list[str]) -> CommandResult:
    if len(arguments) != 1:
        return INVALID_ARGS, True
    option = arguments[0]
    if option.casefold().startswith("--author="):
        return _format_commits(repository.search_author(option.split("=", 1)[1])), True
    return _format_commits(repository.search_keyword(option)), True


def _exit(repository: Repository, arguments: list[str]) -> CommandResult:
    del repository
    return ("", False) if not arguments else (INVALID_ARGS, True)


_COMMANDS: Final[dict[str, CommandHandler]] = {
    "init": _init,
    "branch": _branch,
    "switch": _switch,
    "commit": _commit,
    "merge": _merge,
    "log": _log,
    "path": _path,
    "ancestors": _ancestors,
    "search": _search,
    "exit": _exit,
    "quit": _exit,
}


def _format_path(path: list[CommitId] | None) -> str:
    if path is None:
        return "No path"
    return "Path: " + " -> ".join(path)


def _format_commits(commits: list[Commit]) -> str:
    if not commits:
        return "No commits"
    return "\n".join(_format_commit(commit) for commit in commits)


def _format_commit(commit: Commit) -> str:
    timestamp = _format_timestamp(commit.timestamp)
    parents = ",".join(commit.parents) if commit.parents else "none"
    return (
        f"commit {commit.commit_id} ({commit.author}, {timestamp}) "
        f"parents={parents}\n{commit.message}"
    )


def _format_timestamp(timestamp: datetime) -> str:
    return timestamp.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
