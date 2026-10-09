import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from book_catalog.models.book import Book


def test_book_inventory_constraint_is_enforced_by_database(db: Session) -> None:
    db.add(Book(title="Invalid", author="Author", year=2020, total_copies=0))

    with pytest.raises(IntegrityError):
        db.commit()
