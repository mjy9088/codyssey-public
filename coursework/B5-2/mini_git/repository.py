"""In-memory repository state and inverted indexes."""

from collections.abc import Callable
from datetime import datetime
from enum import StrEnum
from typing import Final, assert_never

from mini_git.algorithms import ancestor_ids, merge_sort, shortest_path, topological_commits
from mini_git.errors import (
    BranchExistsError,
    EmptyValueError,
    MergeUnavailableError,
    RepositoryNotInitializedError,
    UnknownBranchError,
    UnknownCommitError,
)
from mini_git.model import Commit, CommitId

ID_WIDTH: Final = 10


class SortMode(StrEnum):
    """Supported explicit log orderings."""

    DATE = "date"
    AUTHOR = "author"


class Repository:
    """Mutable in-memory state machine for Mini Git operations."""

    def __init__(self, clock: Callable[[], datetime]) -> None:
        """Create empty state using an injected timestamp source."""
        self._clock: Callable[[], datetime] = clock
        self._user: str | None = None
        self._current_branch: str | None = None
        self._commits: dict[CommitId, Commit] = {}
        self._branches: dict[str, CommitId | None] = {}
        self._keyword_index: dict[str, list[CommitId]] = {}
        self._author_index: dict[str, list[CommitId]] = {}
        self._sequence: int = 0

    def initialize(self, user: str) -> None:
        """Reset state and create the main branch for a user."""
        normalized = user.strip()
        if not normalized:
            raise EmptyValueError(field="user")
        self._user = normalized
        self._current_branch = "main"
        self._commits = {}
        self._branches = {"main": None}
        self._keyword_index = {}
        self._author_index = {}

    def commit(self, message: str) -> Commit:
        """Append a commit to the current branch and update indexes."""
        user, branch = self._identity()
        normalized = message.strip()
        if not normalized:
            raise EmptyValueError(field="message")
        timestamp = self._clock()
        parent = self._branches[branch]
        parents = () if parent is None else (parent,)
        commit = self._new_commit(normalized, user, timestamp, parents)
        self._record(commit, branch)
        return commit

    def branch(self, name: str) -> None:
        """Create a branch at the current branch tip."""
        _, current = self._identity()
        normalized = name.strip()
        if not normalized:
            raise EmptyValueError(field="branch")
        if normalized in self._branches:
            raise BranchExistsError(name=normalized)
        self._branches[normalized] = self._branches[current]

    def switch(self, name: str) -> None:
        """Select an existing branch."""
        _ = self._identity()
        if name not in self._branches:
            raise UnknownBranchError(name=name)
        self._current_branch = name

    def merge(self, name: str) -> Commit:
        """Create a two-parent commit with another branch tip."""
        user, current = self._identity()
        if name not in self._branches:
            raise UnknownBranchError(name=name)
        current_tip = self._branches[current]
        target_tip = self._branches[name]
        if current_tip is None or target_tip is None or current_tip == target_tip:
            raise MergeUnavailableError(name=name)
        commit = self._new_commit(
            f"Merge branch '{name}'",
            user,
            self._clock(),
            (current_tip, target_tip),
        )
        self._record(commit, current)
        return commit

    def log(self, sort_by: str | None = None) -> list[Commit]:
        """Return topological or explicitly sorted commit history."""
        _ = self._identity()
        commits = list(self._commits.values())
        if sort_by is None:
            return topological_commits(commits)
        try:
            mode = SortMode(sort_by.lower())
        except ValueError as error:
            raise EmptyValueError(field="sort") from error
        match mode:
            case SortMode.DATE:
                return merge_sort(
                    commits,
                    key=lambda item: (item.timestamp.isoformat(), item.commit_id),
                )
            case SortMode.AUTHOR:
                return merge_sort(
                    commits,
                    key=lambda item: (
                        item.author.casefold(),
                        item.timestamp.isoformat(),
                        item.commit_id,
                    ),
                )
        assert_never(mode)

    def path(self, start: str, end: str) -> list[CommitId] | None:
        """Find an undirected shortest path between known commits."""
        _ = self._identity()
        start_id = self._known_commit(start)
        end_id = self._known_commit(end)
        return shortest_path(list(self._commits.values()), start_id, end_id)

    def ancestors(self, commit_id: str) -> list[Commit]:
        """Return every reachable ancestor of a known commit."""
        _ = self._identity()
        start = self._known_commit(commit_id)
        return [self._commits[item] for item in ancestor_ids(list(self._commits.values()), start)]

    def search_keyword(self, keyword: str) -> list[Commit]:
        """Look up an exact normalized message token in the inverted index."""
        _ = self._identity()
        normalized = keyword.strip().casefold()
        if not normalized:
            raise EmptyValueError(field="keyword")
        return [self._commits[item] for item in self._keyword_index.get(normalized, [])]

    def search_author(self, author: str) -> list[Commit]:
        """Look up a normalized author in the inverted index."""
        _ = self._identity()
        normalized = author.strip().casefold()
        if not normalized:
            raise EmptyValueError(field="author")
        return [self._commits[item] for item in self._author_index.get(normalized, [])]

    def _identity(self) -> tuple[str, str]:
        if self._user is None or self._current_branch is None:
            raise RepositoryNotInitializedError
        return self._user, self._current_branch

    def _known_commit(self, raw_id: str) -> CommitId:
        commit_id = CommitId(raw_id)
        if commit_id not in self._commits:
            raise UnknownCommitError(commit_id=raw_id)
        return commit_id

    def _new_commit(
        self,
        message: str,
        author: str,
        timestamp: datetime,
        parents: tuple[CommitId, ...],
    ) -> Commit:
        self._sequence += 1
        commit_id = CommitId(f"{self._sequence:0{ID_WIDTH}x}")
        return Commit(commit_id, message, author, timestamp, parents)

    def _record(self, commit: Commit, branch: str) -> None:
        self._commits[commit.commit_id] = commit
        self._branches[branch] = commit.commit_id
        self._author_index.setdefault(commit.author.casefold(), []).append(commit.commit_id)
        for token in set(commit.message.casefold().split()):
            self._keyword_index.setdefault(token, []).append(commit.commit_id)
