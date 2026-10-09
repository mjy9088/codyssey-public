from __future__ import annotations

from dataclasses import dataclass
from typing import NewType

BookId = NewType("BookId", int)
MIN_YEAR = 1450
MAX_YEAR = 2100
MAX_TITLE_LENGTH = 160
MAX_AUTHOR_LENGTH = 120


@dataclass(frozen=True, slots=True)
class BookInput:
    """Normalized book fields accepted by the service layer."""

    title: str
    author: str
    year: int

    @classmethod
    def parse(cls, *, title: str, author: str, year: str) -> BookInput | InvalidBookInput:
        """Parse untrusted form strings once at the HTTP boundary."""
        clean_title = " ".join(title.split())
        clean_author = " ".join(author.split())
        clean_year = year.strip()
        invalid: set[str] = set()
        if not clean_title or len(clean_title) > MAX_TITLE_LENGTH:
            invalid.add("title")
        if not clean_author or len(clean_author) > MAX_AUTHOR_LENGTH:
            invalid.add("author")
        parsed_year = int(clean_year) if clean_year.isdecimal() else 0
        if not MIN_YEAR <= parsed_year <= MAX_YEAR:
            invalid.add("year")
        if invalid:
            return InvalidBookInput(
                title=title,
                author=author,
                year=year,
                fields=frozenset(invalid),
            )
        return cls(title=clean_title, author=clean_author, year=parsed_year)


@dataclass(frozen=True, slots=True)
class InvalidBookInput:
    """Rejected form values retained for accessible re-rendering."""

    title: str
    author: str
    year: str
    fields: frozenset[str]


@dataclass(frozen=True, slots=True)
class BookView:
    """Immutable record exposed above the persistence layer."""

    id: BookId
    title: str
    author: str
    year: int
