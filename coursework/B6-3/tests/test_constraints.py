from datetime import datetime, timedelta

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from book_catalog.models.book import Book
from book_catalog.models.loan import Loan
from book_catalog.models.session import ServerSession
from book_catalog.models.user import User
from book_catalog.repositories.sessions import token_digest


def test_book_inventory_constraint_is_enforced_by_database(db: Session) -> None:
    db.add(Book(title="Invalid", author="Author", year=2020, total_copies=0))

    with pytest.raises(IntegrityError):
        db.commit()


def test_user_deletion_cascades_owned_loans_and_sessions(db: Session, fixed_now: datetime) -> None:
    # Given
    user = db.query(User).one()
    book = db.query(Book).one()
    db.add(Loan(user_id=user.id, book_id=book.id, borrowed_at=fixed_now))
    db.add(
        ServerSession(
            user_id=user.id,
            token_digest=token_digest("cascade-session"),
            expires_at=fixed_now + timedelta(hours=1),
        )
    )
    db.commit()

    # When
    db.delete(user)
    db.commit()

    # Then
    assert db.scalar(select(func.count()).select_from(Loan)) == 0
    assert db.scalar(select(func.count()).select_from(ServerSession)) == 0


def test_database_restricts_book_deletion_when_loan_history_exists(
    db: Session, fixed_now: datetime
) -> None:
    # Given
    user = db.query(User).one()
    book = db.query(Book).one()
    db.add(Loan(user_id=user.id, book_id=book.id, borrowed_at=fixed_now))
    db.commit()

    # When / Then
    db.delete(book)
    with pytest.raises(IntegrityError):
        db.commit()
