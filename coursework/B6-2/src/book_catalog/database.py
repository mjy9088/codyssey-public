from collections.abc import Generator
from os import environ
from pathlib import Path
from typing import Final

from sqlalchemy import Engine, create_engine, event
from sqlalchemy.engine.interfaces import DBAPIConnection
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import ConnectionPoolEntry

from book_catalog.models.base import Base

DEFAULT_DATABASE_URL: Final = "sqlite+pysqlite:///data/catalog.db"
DATABASE_URL: Final = environ.get("CATALOG_DATABASE_URL", DEFAULT_DATABASE_URL)


def _prepare_sqlite_path(url: str) -> None:
    prefix = "sqlite+pysqlite:///"
    if url.startswith(prefix) and ":memory:" not in url:
        Path(url.removeprefix(prefix)).parent.mkdir(parents=True, exist_ok=True)


_prepare_sqlite_path(DATABASE_URL)
engine: Final[Engine] = create_engine(DATABASE_URL, pool_pre_ping=True)


@event.listens_for(engine, "connect")
def _enable_sqlite_foreign_keys(
    dbapi_connection: DBAPIConnection,
    _connection_record: ConnectionPoolEntry,
) -> None:
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


session_factory: Final = sessionmaker(engine, expire_on_commit=False)


def initialize_database() -> None:
    Base.metadata.create_all(engine)


def get_session() -> Generator[Session]:
    with session_factory() as session:
        yield session
