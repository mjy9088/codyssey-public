from datetime import datetime

import pytest
from sqlalchemy.orm import Session

from book_catalog.models.book import Book
from book_catalog.models.user import User
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.schemas.domain import BookInput, UserId
from book_catalog.services.books import BookHasLoansError, BookInventoryConflictError, BookService
from book_catalog.services.loans import LoanService


def test_delete_rejects_book_with_lending_history(db: Session, fixed_now: datetime) -> None:
    book = db.query(Book).one()
    user = db.query(User).one()
    _ = LoanService(LoanRepository(db), BookRepository(db), lambda: fixed_now).borrow(
        UserId(user.id), book.id
    )

    with pytest.raises(BookHasLoansError):
        BookService(BookRepository(db)).delete(book.id)


def test_update_rejects_inventory_below_active_loans(db: Session, fixed_now: datetime) -> None:
    book = db.query(Book).one()
    book.total_copies = 2
    second_user = User("second-reader", "Second Reader", "unused")
    db.add(second_user)
    db.commit()
    first_user = db.query(User).filter_by(username="reader").one()
    loans = LoanService(LoanRepository(db), BookRepository(db), lambda: fixed_now)
    _ = loans.borrow(UserId(first_user.id), book.id)
    _ = loans.borrow(UserId(second_user.id), book.id)

    with pytest.raises(BookInventoryConflictError):
        _ = BookService(BookRepository(db)).update(
            book.id,
            BookInput("Kindred", "Octavia Butler", 1979, 1),
        )
