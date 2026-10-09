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
