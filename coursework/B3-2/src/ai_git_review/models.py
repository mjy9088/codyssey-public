from dataclasses import dataclass
from enum import StrEnum


class ReviewKind(StrEnum):
    COMMIT = "commit"
    PR = "pr"


@dataclass(frozen=True, slots=True)
class ChangeContext:
    status: str
    diff: str
    files: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class GenerationOptions:
    model: str
    temperature: float
    max_tokens: int


@dataclass(frozen=True, slots=True)
class ReviewResult:
    kind: ReviewKind
    title: str
    body: str
