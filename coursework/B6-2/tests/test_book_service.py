from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from book_catalog.models.base import Base
from book_catalog.repositories.books import BookRepository
from book_catalog.schemas.books import BookInput
from book_catalog.services.books import BookService


def test_service_crud_uses_real_sqlite(tmp_path: Path) -> None:
    engine = create_engine(f"sqlite+pysqlite:///{tmp_path / 'catalog.db'}")
    Base.metadata.create_all(engine)
    draft = BookInput(title="Kindred", author="Octavia Butler", year=1979)

    with Session(engine) as session:
        service = BookService(BookRepository(session))
        created = service.create(draft)
        updated = service.update(
            created.id,
            BookInput(title="Kindred", author="O. E. Butler", year=1979),
        )

        assert updated.author == "O. E. Butler"
        assert service.get(created.id).title == "Kindred"
        service.delete(created.id)

    engine.dispose()


def test_created_book_survives_engine_and_session_restart(tmp_path: Path) -> None:
    # Given
    database_url = f"sqlite+pysqlite:///{tmp_path / 'persistent-catalog.db'}"
    first_engine = create_engine(database_url)
    Base.metadata.create_all(first_engine)
    with Session(first_engine) as first_session:
        created = BookService(BookRepository(first_session)).create(
            BookInput(title="Parable of the Sower", author="Octavia Butler", year=1993)
        )
    first_engine.dispose()

    # When
    restarted_engine = create_engine(database_url)
    with Session(restarted_engine) as restarted_session:
        persisted = BookService(BookRepository(restarted_session)).get(created.id)

    # Then
    assert persisted.title == "Parable of the Sower"
    assert persisted.author == "Octavia Butler"
    restarted_engine.dispose()
