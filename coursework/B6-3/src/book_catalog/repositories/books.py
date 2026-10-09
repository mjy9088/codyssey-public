from typing import final

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from book_catalog.models.book import Book
from book_catalog.models.loan import Loan, LoanStatus
from book_catalog.schemas.domain import BookInput


@final
class BookRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def list(self, query: str) -> tuple[Book, ...]:
        statement = select(Book).order_by(Book.title, Book.id)
        if query:
            pattern = f"%{query}%"
            statement = statement.where(or_(Book.title.ilike(pattern), Book.author.ilike(pattern)))
        return tuple(self._session.scalars(statement).all())

    def get(self, book_id: int) -> Book | None:
        return self._session.get(Book, book_id)

    def active_count(self, book_id: int) -> int:
        statement = (
            select(func.count())
            .select_from(Loan)
            .where(Loan.book_id == book_id, Loan.status == LoanStatus.BORROWED)
        )
        return int(self._session.scalar(statement) or 0)

    def has_loan_history(self, book_id: int) -> bool:
        statement = select(Loan.id).where(Loan.book_id == book_id).limit(1)
        return self._session.scalar(statement) is not None

    def create(self, draft: BookInput) -> Book:
        book = Book(
            title=draft.title,
            author=draft.author,
            year=draft.year,
            total_copies=draft.total_copies,
        )
        self._session.add(book)
        self._session.commit()
        self._session.refresh(book)
        return book

    def update(self, book: Book, draft: BookInput) -> Book:
        book.title, book.author = draft.title, draft.author
        book.year, book.total_copies = draft.year, draft.total_copies
        self._session.commit()
        self._session.refresh(book)
        return book

    def delete(self, book: Book) -> None:
        self._session.delete(book)
        self._session.commit()
