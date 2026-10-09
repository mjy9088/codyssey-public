from typing import final

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from book_catalog.models.book import Book
from book_catalog.schemas.books import BookId, BookInput


@final
class BookRepository:
    """Own all database access for books."""

    def __init__(self, session: Session) -> None:
        self._session: Session = session

    def list(self, query: str) -> tuple[Book, ...]:
        statement = select(Book).order_by(Book.title, Book.author, Book.id)
        if query:
            pattern = f"%{query}%"
            statement = statement.where(or_(Book.title.ilike(pattern), Book.author.ilike(pattern)))
        return tuple(self._session.scalars(statement).all())

    def get(self, book_id: BookId) -> Book | None:
        return self._session.get(Book, int(book_id))

    def create(self, draft: BookInput) -> Book:
        book = Book(title=draft.title, author=draft.author, year=draft.year)
        self._session.add(book)
        self._session.commit()
        self._session.refresh(book)
        return book

    def update(self, book: Book, draft: BookInput) -> Book:
        book.title = draft.title
        book.author = draft.author
        book.year = draft.year
        self._session.commit()
        self._session.refresh(book)
        return book

    def delete(self, book: Book) -> None:
        self._session.delete(book)
        self._session.commit()
