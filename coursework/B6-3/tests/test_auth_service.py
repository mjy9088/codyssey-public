from datetime import datetime

import pytest
from sqlalchemy.orm import Session

from book_catalog.auth.passwords import hash_password
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
