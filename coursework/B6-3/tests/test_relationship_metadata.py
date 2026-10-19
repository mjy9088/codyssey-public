from sqlalchemy import inspect

from book_catalog.models.book import Book
from book_catalog.models.loan import Loan
from book_catalog.models.session import ServerSession
from book_catalog.models.user import User


def test_orm_relationships_are_bidirectional_with_explicit_ownership() -> None:
    # Given / When
    user_relationships = inspect(User).relationships
    book_relationships = inspect(Book).relationships
    loan_relationships = inspect(Loan).relationships
    session_relationships = inspect(ServerSession).relationships

    # Then
    assert user_relationships.loans.back_populates == "user"
    assert user_relationships.sessions.back_populates == "user"
    assert book_relationships.loans.back_populates == "book"
    assert loan_relationships.user.back_populates == "loans"
    assert loan_relationships.book.back_populates == "loans"
    assert session_relationships.user.back_populates == "sessions"
    assert user_relationships.loans.direction.name == "ONETOMANY"
    assert user_relationships.sessions.direction.name == "ONETOMANY"
    assert loan_relationships.user.direction.name == "MANYTOONE"
    assert loan_relationships.book.direction.name == "MANYTOONE"
    assert "delete-orphan" in user_relationships.loans.cascade
    assert "delete-orphan" in user_relationships.sessions.cascade
    assert "delete" not in book_relationships.loans.cascade


def test_foreign_keys_declare_user_cascade_and_book_restriction() -> None:
    # Given / When
    foreign_keys = {
        column.name: next(iter(column.foreign_keys)).ondelete
        for column in inspect(Loan).columns
        if column.foreign_keys
    }
    session_user_key = next(iter(inspect(ServerSession).columns.user_id.foreign_keys))

    # Then
    assert foreign_keys == {"user_id": "CASCADE", "book_id": "RESTRICT"}
    assert session_user_key.ondelete == "CASCADE"
