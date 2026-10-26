from pathlib import Path

from sqlalchemy import Engine, create_engine, func, select
from sqlalchemy.orm import Session

from book_catalog.auth.passwords import verify_password
from book_catalog.models import Base, Book, User
from book_catalog.seed import seed_database


def _seeded_database(path: Path) -> tuple[Engine, str, tuple[str, ...]]:
    engine = create_engine(f"sqlite+pysqlite:///{path}")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        seed_database(session)
        seed_database(session)
        password_hash = session.scalar(select(User.password_hash))
        assert password_hash is not None
        assert session.scalar(select(User.username)) == "reader"
        assert session.scalar(select(func.count()).select_from(User)) == 1
        assert session.scalar(select(func.count()).select_from(Book)) == 3
        book_titles = tuple(session.scalars(select(Book.title).order_by(Book.id)))
    return engine, password_hash, book_titles


def test_seed_data_is_idempotent_and_deterministic(tmp_path: Path) -> None:
    # Given / When
    first_engine, first_hash, first_titles = _seeded_database(tmp_path / "first.db")
    second_engine, second_hash, second_titles = _seeded_database(tmp_path / "second.db")

    # Then
    assert verify_password("correct-horse-battery-staple", first_hash)
    assert verify_password("correct-horse-battery-staple", second_hash)
    assert first_titles == second_titles == ("Kindred", "The Dispossessed", "Piranesi")
    first_engine.dispose()
    second_engine.dispose()
