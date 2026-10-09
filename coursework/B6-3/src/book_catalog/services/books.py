from dataclasses import dataclass
from typing import final, override

from book_catalog.models.book import Book
from book_catalog.repositories.books import BookRepository
from book_catalog.schemas.domain import BookId, BookInput, BookView


@dataclass(frozen=True, slots=True)
class BookNotFoundError(Exception):
    book_id: int

    @override
    def __str__(self) -> str:
        return f"book {self.book_id} not found"


@dataclass(frozen=True, slots=True)
class BookHasLoansError(Exception):
    book_id: int

    @override
    def __str__(self) -> str:
        return f"book {self.book_id} has lending history"


@dataclass(frozen=True, slots=True)
class BookInventoryConflictError(Exception):
    book_id: int
    active_loans: int
    requested_copies: int

    @override
    def __str__(self) -> str:
        return f"Inventory cannot be lower than {self.active_loans} active loans"


@final
class BookService:
    def __init__(self, repository: BookRepository) -> None:
        self._repository = repository

    def list(self, query: str = "") -> tuple[BookView, ...]:
        normalized = " ".join(query.split())[:80]
        return tuple(self._view(book) for book in self._repository.list(normalized))

    def get(self, book_id: int) -> BookView:
        return self._view(self._require(book_id))

    def create(self, draft: BookInput) -> BookView:
        return self._view(self._repository.create(draft))

    def update(self, book_id: int, draft: BookInput) -> BookView:
        book = self._require(book_id)
        active_loans = self._repository.active_count(book_id)
        if draft.total_copies < active_loans:
            raise BookInventoryConflictError(book_id, active_loans, draft.total_copies)
        return self._view(self._repository.update(book, draft))

    def delete(self, book_id: int) -> None:
        if self._repository.has_loan_history(book_id):
            raise BookHasLoansError(book_id)
        self._repository.delete(self._require(book_id))

    def _require(self, book_id: int) -> Book:
        book = self._repository.get(book_id)
        if book is None:
            raise BookNotFoundError(book_id)
        return book

    def _view(self, book: Book) -> BookView:
        active = self._repository.active_count(book.id)
        return BookView(
            BookId(book.id),
            book.title,
            book.author,
            book.year,
            book.total_copies,
            book.total_copies - active,
        )
