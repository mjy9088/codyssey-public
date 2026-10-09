from datetime import datetime

import pytest
from sqlalchemy.orm import Session

from book_catalog.models.book import Book
from book_catalog.models.user import User
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.schemas.domain import UserId
from book_catalog.services.loans import LoanRuleError, LoanService


def service(db: Session, now: datetime) -> LoanService:
    return LoanService(LoanRepository(db), BookRepository(db), lambda: now)


def test_borrow_and_return_are_persisted_relationship_transitions(
    db: Session, fixed_now: datetime
) -> None:
    user = db.query(User).one()
    book = db.query(Book).one()
    loans = service(db, fixed_now)

    borrowed = loans.borrow(UserId(user.id), book.id)
    returned = loans.return_loan(UserId(user.id), borrowed.id)

    assert borrowed.status == "borrowed"
    assert borrowed.book.available_copies == 0
    assert returned.status == "returned"
    assert returned.returned_at == fixed_now
    assert returned.borrower_name == "Demo Reader"


def test_borrow_rejects_duplicate_and_unavailable_copy(db: Session, fixed_now: datetime) -> None:
    first = db.query(User).one()
    second = User("second", "Second Reader", "unused")
    db.add(second)
    db.commit()
    book = db.query(Book).one()
    loans = service(db, fixed_now)
    _ = loans.borrow(UserId(first.id), book.id)

    with pytest.raises(LoanRuleError, match="already on your account"):
        _ = loans.borrow(UserId(first.id), book.id)
    with pytest.raises(LoanRuleError, match="No copy"):
        _ = loans.borrow(UserId(second.id), book.id)


def test_return_rejects_other_user_and_second_transition(db: Session, fixed_now: datetime) -> None:
    owner = db.query(User).one()
    other = User("other", "Other Reader", "unused")
    db.add(other)
    db.commit()
    loans = service(db, fixed_now)
    borrowed = loans.borrow(UserId(owner.id), db.query(Book).one().id)

    with pytest.raises(LoanRuleError, match="Loan not found"):
        _ = loans.return_loan(UserId(other.id), borrowed.id)
    _ = loans.return_loan(UserId(owner.id), borrowed.id)
    with pytest.raises(LoanRuleError, match="already returned"):
        _ = loans.return_loan(UserId(owner.id), borrowed.id)
