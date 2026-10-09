"""Typed domain errors translated at the CLI boundary."""

from dataclasses import dataclass

from typing_extensions import override


class MiniGitError(RuntimeError):
    """Base class for expected command failures."""


@dataclass(frozen=True, slots=True)
class RepositoryNotInitializedError(MiniGitError):
    @override
    def __str__(self) -> str:
        return "Repository not initialized"


@dataclass(frozen=True, slots=True)
class BranchExistsError(MiniGitError):
    name: str

    @override
    def __str__(self) -> str:
        return f"Branch already exists: {self.name}"


@dataclass(frozen=True, slots=True)
class UnknownBranchError(MiniGitError):
    name: str

    @override
    def __str__(self) -> str:
        return f"Unknown branch: {self.name}"


@dataclass(frozen=True, slots=True)
class UnknownCommitError(MiniGitError):
    commit_id: str

    @override
    def __str__(self) -> str:
        return f"Unknown commit: {self.commit_id}"


@dataclass(frozen=True, slots=True)
class EmptyValueError(MiniGitError):
    field: str

    @override
    def __str__(self) -> str:
        return "Invalid args"


@dataclass(frozen=True, slots=True)
class MergeUnavailableError(MiniGitError):
    name: str

    @override
    def __str__(self) -> str:
        return f"Cannot merge branch: {self.name}"


@dataclass(frozen=True, slots=True)
class GraphInvariantError(MiniGitError):
    @override
    def __str__(self) -> str:
        return "Commit graph is not a DAG"
