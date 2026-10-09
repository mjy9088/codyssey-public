from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import assert_never, final, override

from book_catalog.models.loan import Loan, LoanStatus
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.schemas.domain import BookId, BookView, LoanId, LoanView, UserId


class LoanRule(StrEnum):
    BOOK_MISSING = "Book not found"
    DUPLICATE = "This book is already on your account"
    UNAVAILABLE = "No copy is currently available"
    LOAN_MISSING = "Loan not found"
    RETURNED = "Loan is already returned"


@dataclass(frozen=True, slots=True)
class LoanRuleError(Exception):
    rule: LoanRule

    @override
    def __str__(self) -> str:
        match self.rule:
            case LoanRule.BOOK_MISSING:
                return LoanRule.BOOK_MISSING
            case LoanRule.DUPLICATE:
                return LoanRule.DUPLICATE
            case LoanRule.UNAVAILABLE:
                return LoanRule.UNAVAILABLE
            case LoanRule.LOAN_MISSING:
                return LoanRule.LOAN_MISSING
            case LoanRule.RETURNED:
                return LoanRule.RETURNED
            case unreachable:
                assert_never(unreachable)


@final
class LoanService:
    def __init__(
        self,
        loans: LoanRepository,
        books: BookRepository,
        clock: Callable[[], datetime],
    ) -> None:
        self._loans = loans
        self._books = books
        self._clock = clock

    def list(self, user_id: UserId, status: str) -> tuple[LoanView, ...]:
        normalized = None if status == "all" else status
        if normalized not in {None, LoanStatus.BORROWED, LoanStatus.RETURNED}:
            normalized = LoanStatus.BORROWED
        return tuple(self._view(loan) for loan in self._loans.list_for_user(user_id, normalized))

    def borrow(self, user_id: UserId, book_id: int) -> LoanView:
        book = self._books.get(book_id)
        if book is None:
            raise LoanRuleError(LoanRule.BOOK_MISSING)
        if self._loans.active_for_book(user_id, book_id) is not None:
            raise LoanRuleError(LoanRule.DUPLICATE)
        if self._books.active_count(book_id) >= book.total_copies:
            raise LoanRuleError(LoanRule.UNAVAILABLE)
        return self._view(self._loans.create(user_id, book_id, self._clock()))

    def return_loan(self, user_id: UserId, loan_id: int) -> LoanView:
        loan = self._loans.get(loan_id)
        if loan is None or loan.user_id != user_id:
            raise LoanRuleError(LoanRule.LOAN_MISSING)
        if loan.status != LoanStatus.BORROWED:
            raise LoanRuleError(LoanRule.RETURNED)
        return self._view(self._loans.mark_returned(loan, self._clock()))

    def _view(self, loan: Loan) -> LoanView:
        book = loan.book
        available = book.total_copies - self._books.active_count(book.id)
        book_view = BookView(
            BookId(book.id), book.title, book.author, book.year, book.total_copies, available
        )
        return LoanView(
            LoanId(loan.id),
            loan.status,
            _as_utc(loan.borrowed_at),
            None if loan.returned_at is None else _as_utc(loan.returned_at),
            book_view,
            loan.user.full_name,
        )


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
