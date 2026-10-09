from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Final, NewType

if TYPE_CHECKING:
    from datetime import datetime

EARLIEST_BOOK_YEAR: Final = 1450
LATEST_BOOK_YEAR: Final = 2100

UserId = NewType("UserId", int)
BookId = NewType("BookId", int)
LoanId = NewType("LoanId", int)


@dataclass(frozen=True, slots=True)
class UserView:
    id: UserId
    username: str
    full_name: str


@dataclass(frozen=True, slots=True)
class BookView:
    id: BookId
    title: str
    author: str
    year: int
    total_copies: int
    available_copies: int


@dataclass(frozen=True, slots=True)
class LoanView:
    id: LoanId
    status: str
    borrowed_at: datetime
    returned_at: datetime | None
    book: BookView
    borrower_name: str


@dataclass(frozen=True, slots=True)
class BookInput:
    title: str
    author: str
    year: int
    total_copies: int

    @classmethod
    def parse(cls, title: str, author: str, year: str, total_copies: str) -> BookInput | None:
        clean_title = " ".join(title.split())
        clean_author = " ".join(author.split())
        clean_year = int(year) if year.isdecimal() else 0
        clean_copies = int(total_copies) if total_copies.isdecimal() else 0
        if not clean_title or not clean_author:
            return None
        if not EARLIEST_BOOK_YEAR <= clean_year <= LATEST_BOOK_YEAR or clean_copies < 1:
            return None
        return cls(clean_title, clean_author, clean_year, clean_copies)
