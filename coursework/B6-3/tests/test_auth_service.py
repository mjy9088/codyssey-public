from datetime import datetime
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from book_catalog.auth.passwords import hash_password
from book_catalog.models import Base
from book_catalog.models.user import User
from book_catalog.repositories.sessions import SessionRepository
from book_catalog.repositories.users import UserRepository
from book_catalog.services.auth import AuthService, InvalidCredentialsError


def test_login_persists_opaque_session_and_logout_invalidates_it(
    db: Session, fixed_now: datetime
) -> None:
    user = db.query(User).filter_by(username="reader").one()
    user.password_hash = hash_password("secret", salt=b"0123456789abcdef")
    db.commit()
    service = AuthService(
        UserRepository(db), SessionRepository(db), lambda: fixed_now, lambda: "raw-session-token"
    )

    context = service.login("reader", "secret")
    authenticated = service.authenticate("raw-session-token")
    service.logout("raw-session-token")

    assert context.user.username == "reader"
    assert authenticated == context
    assert service.authenticate("raw-session-token") is None


def test_login_rejects_wrong_password(db: Session, fixed_now: datetime) -> None:
    service = AuthService(UserRepository(db), SessionRepository(db), lambda: fixed_now)

    with pytest.raises(InvalidCredentialsError):
        _ = service.login("reader", "wrong")


def test_session_authentication_survives_storage_restart(
    tmp_path: Path, fixed_now: datetime
) -> None:
    # Given
    database_url = f"sqlite+pysqlite:///{tmp_path / 'persistent-sessions.db'}"
    first_engine = create_engine(database_url)
    Base.metadata.create_all(first_engine)
    with Session(first_engine) as first_db:
        first_db.add(
            User(
                "restart-reader",
                "Restart Reader",
                hash_password("restart-secret", salt=b"0123456789abcdef"),
            )
        )
        first_db.commit()
        context = AuthService(
            UserRepository(first_db),
            SessionRepository(first_db),
            lambda: fixed_now,
            lambda: "persistent-session-token",
        ).login("restart-reader", "restart-secret")
    first_engine.dispose()

    # When
    restarted_engine = create_engine(database_url)
    with Session(restarted_engine) as restarted_db:
        authenticated = AuthService(
            UserRepository(restarted_db), SessionRepository(restarted_db), lambda: fixed_now
        ).authenticate(context.raw_session)

    # Then
    assert authenticated == context
    restarted_engine.dispose()
