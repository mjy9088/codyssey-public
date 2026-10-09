from collections.abc import Generator
from os import environ
from pathlib import Path
from typing import Final

from sqlalchemy import Engine, create_engine, event, select
from sqlalchemy.engine.interfaces import DBAPIConnection
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import ConnectionPoolEntry

from book_catalog.auth.passwords import hash_password
from book_catalog.models import Base, Book, User

DEFAULT_DATABASE_URL: Final = "sqlite+pysqlite:///data/catalog.db"
DATABASE_URL: Final = environ.get("CATALOG_DATABASE_URL", DEFAULT_DATABASE_URL)


def _prepare_path(url: str) -> None:
    prefix = "sqlite+pysqlite:///"
    if url.startswith(prefix) and ":memory:" not in url:
        Path(url.removeprefix(prefix)).parent.mkdir(parents=True, exist_ok=True)


engine: Final[Engine] = create_engine(DATABASE_URL, pool_pre_ping=True)
session_factory: Final = sessionmaker(engine, expire_on_commit=False)


@event.listens_for(engine, "connect")
def _foreign_keys(connection: DBAPIConnection, _record: ConnectionPoolEntry) -> None:
    cursor = connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


def initialize_database() -> None:
    _prepare_path(DATABASE_URL)
    Base.metadata.create_all(engine)
    with session_factory() as session:
        if session.scalar(select(User.id).limit(1)) is None:
            session.add(
                User(
                    username="reader",
                    full_name="Demo Reader",
                    password_hash=hash_password("correct-horse-battery-staple"),
                )
            )
        if session.scalar(select(Book.id).limit(1)) is None:
            session.add_all(
                [
                    Book(title="Kindred", author="Octavia Butler", year=1979, total_copies=2),
                    Book(
                        title="The Dispossessed",
                        author="Ursula Le Guin",
                        year=1974,
                        total_copies=1,
                    ),
                    Book(title="Piranesi", author="Susanna Clarke", year=2020, total_copies=3),
                ]
            )
        session.commit()


def get_session() -> Generator[Session]:
    with session_factory() as session:
        yield session
