"""Typed commit model."""

from dataclasses import dataclass
from datetime import datetime
from typing import NewType

CommitId = NewType("CommitId", str)
BranchName = NewType("BranchName", str)


@dataclass(frozen=True, slots=True)
class Commit:
    """Immutable node in the commit graph."""

    commit_id: CommitId
    message: str
    author: str
    timestamp: datetime
    parents: tuple[CommitId, ...]
