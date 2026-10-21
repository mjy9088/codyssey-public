from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress
from datetime import datetime
from pathlib import Path
from threading import Barrier, BrokenBarrierError, local

from sqlalchemy import Engine, create_engine, event, func, select
from sqlalchemy.orm import Session

from book_catalog.models import Base, Book, Loan, User
from book_catalog.models.loan import LoanStatus
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.schemas.domain import BookInput, UserId
from book_catalog.services.books import BookInventoryConflictError, BookService
from book_catalog.services.loans import LoanRuleError, LoanService


def _database(tmp_path: Path, *, copies: int) -> tuple[Engine, int, tuple[int, int]]:
    engine = create_engine(f"sqlite+pysqlite:///{tmp_path / 'concurrent.db'}")
    Base.metadata.create_all(engine)
    with Session(engine, expire_on_commit=False) as session:
        book = Book(title="Concurrency", author="Test Author", year=2026, total_copies=copies)
        first = User("first", "First Reader", "unused")
        second = User("second", "Second Reader", "unused")
        session.add_all((book, first, second))
        session.commit()
        return engine, book.id, (first.id, second.id)


def _synchronize_reads(engine: Engine, predicate: Callable[[str], bool]) -> None:
    barrier = Barrier(2)
    thread_state = local()

    @event.listens_for(engine, "after_cursor_execute")
    def wait_after_matching_read(
        _connection: object,
        _cursor: object,
        statement: str,
        _parameters: object,
        _context: object,
        _many: bool,
    ) -> None:
        if (
            statement.lstrip().upper().startswith("SELECT")
            and predicate(statement)
            and not getattr(thread_state, "has_waited", False)
        ):
            thread_state.has_waited = True
            with suppress(BrokenBarrierError):
                _ = barrier.wait(timeout=1)


def _borrow(engine: Engine, user_id: int, book_id: int, now: datetime) -> str:
    with Session(engine, expire_on_commit=False) as session:
        service = LoanService(LoanRepository(session), BookRepository(session), lambda: now)
        try:
            _ = service.borrow(UserId(user_id), book_id)
        except LoanRuleError as error:
            return error.rule.value
        return "created"


def test_concurrent_borrowers_cannot_exceed_copy_capacity(
    tmp_path: Path, fixed_now: datetime
) -> None:
    # Given
    engine, book_id, user_ids = _database(tmp_path, copies=1)
    _synchronize_reads(
        engine,
        lambda statement: "count(*)" in statement.casefold() and "loans.book_id" in statement,
    )

    # When
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = tuple(
            executor.submit(_borrow, engine, user_id, book_id, fixed_now) for user_id in user_ids
        )
        outcomes = tuple(future.result() for future in futures)

    # Then
    with Session(engine) as session:
        active = session.scalar(
            select(func.count()).select_from(Loan).where(Loan.status == LoanStatus.BORROWED)
        )
    engine.dispose()
    assert sorted(outcomes) == ["No copy is currently available", "created"]
    assert active == 1


def test_concurrent_sessions_cannot_create_duplicate_active_loan(
    tmp_path: Path, fixed_now: datetime
) -> None:
    # Given
    engine, book_id, user_ids = _database(tmp_path, copies=2)
    _synchronize_reads(
        engine,
        lambda statement: "loans.user_id" in statement and "loans.status" in statement,
    )

    # When
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = tuple(
            executor.submit(_borrow, engine, user_ids[0], book_id, fixed_now)
            for _attempt in range(2)
        )
        outcomes = tuple(future.result() for future in futures)

    # Then
    with Session(engine) as session:
        active = session.scalar(
            select(func.count()).select_from(Loan).where(Loan.status == LoanStatus.BORROWED)
        )
    engine.dispose()
    assert sorted(outcomes) == ["This book is already on your account", "created"]
    assert active == 1


def test_capacity_update_and_borrow_preserve_inventory_invariant(
    tmp_path: Path, fixed_now: datetime
) -> None:
    # Given
    engine, book_id, user_ids = _database(tmp_path, copies=2)
    assert _borrow(engine, user_ids[0], book_id, fixed_now) == "created"
    _synchronize_reads(
        engine,
        lambda statement: "count(*)" in statement.casefold() and "loans.book_id" in statement,
    )

    def lower_capacity() -> str:
        with Session(engine, expire_on_commit=False) as session:
            try:
                _ = BookService(BookRepository(session)).update(
                    book_id, BookInput("Concurrency", "Test Author", 2026, 1)
                )
            except BookInventoryConflictError:
                return "rejected"
            return "updated"

    # When
    with ThreadPoolExecutor(max_workers=2) as executor:
        update_result = executor.submit(lower_capacity)
        borrow_result = executor.submit(_borrow, engine, user_ids[1], book_id, fixed_now)
        outcomes = (update_result.result(), borrow_result.result())

    # Then
    with Session(engine) as session:
        book = session.get_one(Book, book_id)
        active = session.scalar(
            select(func.count()).select_from(Loan).where(Loan.status == LoanStatus.BORROWED)
        )
    engine.dispose()
    assert outcomes in {
        ("rejected", "created"),
        ("updated", "No copy is currently available"),
    }
    assert active is not None
    assert active <= book.total_copies
