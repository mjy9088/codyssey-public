from datetime import UTC, datetime
from typing import final

from book_catalog.models.loan import Loan, LoanStatus
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.schemas.domain import BookId, BookView, LoanId, LoanView, UserId


@final
class LoanViewAssembler:
    def __init__(self, books: BookRepository) -> None:
        self._books = books

    def build(self, loan: Loan) -> LoanView:
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


@final
class LoanReadService:
    def __init__(self, loans: LoanRepository, books: BookRepository) -> None:
        self._loans = loans
        self._views = LoanViewAssembler(books)

    def list(self, user_id: UserId, status: str) -> tuple[LoanView, ...]:
        normalized = None if status == "all" else status
        if normalized not in {None, LoanStatus.BORROWED, LoanStatus.RETURNED}:
            normalized = LoanStatus.BORROWED
        return tuple(
            self._views.build(loan) for loan in self._loans.list_for_user(user_id, normalized)
        )


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
