from dataclasses import dataclass
from typing import final, override

from book_catalog.models.book import Book
from book_catalog.repositories.books import BookRepository
from book_catalog.schemas.books import BookId, BookInput, BookView


@dataclass(frozen=True, slots=True)
class BookNotFoundError(Exception):
    """Requested book ID does not exist."""

    book_id: BookId

    @override
    def __str__(self) -> str:
        return f"book {self.book_id} not found"


def _view(book: Book) -> BookView:
    return BookView(id=BookId(book.id), title=book.title, author=book.author, year=book.year)


@final
class BookService:
    """Coordinate book rules independently of HTTP and SQLAlchemy details."""

    def __init__(self, repository: BookRepository) -> None:
        self._repository: BookRepository = repository

    def list(self, query: str) -> tuple[BookView, ...]:
        normalized = " ".join(query.split())[:80]
        return tuple(_view(book) for book in self._repository.list(normalized))

    def get(self, book_id: int) -> BookView:
        persisted = self._require(BookId(book_id))
        return _view(persisted)

    def create(self, draft: BookInput) -> BookView:
        return _view(self._repository.create(draft))

    def update(self, book_id: int, draft: BookInput) -> BookView:
        return _view(self._repository.update(self._require(BookId(book_id)), draft))

    def delete(self, book_id: int) -> None:
        self._repository.delete(self._require(BookId(book_id)))

    def _require(self, book_id: BookId) -> Book:
        book = self._repository.get(book_id)
        if book is None:
            raise BookNotFoundError(book_id)
        return book
