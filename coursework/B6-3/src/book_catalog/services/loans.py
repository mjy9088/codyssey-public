from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import assert_never, final, override

from book_catalog.models.loan import LoanStatus
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.schemas.domain import LoanView, UserId
from book_catalog.services.loan_views import LoanViewAssembler


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
        self._views = LoanViewAssembler(books)

    def borrow(self, user_id: UserId, book_id: int) -> LoanView:
        loan = self._loans.create_available(user_id, book_id, self._clock())
        if loan is not None:
            return self._views.build(loan)
        if self._books.get(book_id) is None:
            raise LoanRuleError(LoanRule.BOOK_MISSING)
        if self._loans.active_for_book(user_id, book_id) is not None:
            raise LoanRuleError(LoanRule.DUPLICATE)
        raise LoanRuleError(LoanRule.UNAVAILABLE)

    def return_loan(self, user_id: UserId, loan_id: int) -> LoanView:
        loan = self._loans.get(loan_id)
        if loan is None or loan.user_id != user_id:
            raise LoanRuleError(LoanRule.LOAN_MISSING)
        if loan.status != LoanStatus.BORROWED:
            raise LoanRuleError(LoanRule.RETURNED)
        return self._views.build(self._loans.mark_returned(loan, self._clock()))
