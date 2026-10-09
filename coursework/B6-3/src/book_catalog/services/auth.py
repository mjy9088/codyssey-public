from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from secrets import token_urlsafe
from typing import final, override

from book_catalog.auth.passwords import verify_password
from book_catalog.repositories.sessions import SessionRepository
from book_catalog.repositories.users import UserRepository
from book_catalog.schemas.domain import UserId, UserView


@dataclass(frozen=True, slots=True)
class AuthContext:
    user: UserView
    raw_session: str


@dataclass(frozen=True, slots=True)
class InvalidCredentialsError(Exception):
    @override
    def __str__(self) -> str:
        return "Invalid username or password"


@final
class AuthService:
    def __init__(
        self,
        users: UserRepository,
        sessions: SessionRepository,
        clock: Callable[[], datetime],
        token_factory: Callable[[], str] = lambda: token_urlsafe(32),
    ) -> None:
        self._users = users
        self._sessions = sessions
        self._clock = clock
        self._token_factory = token_factory

    def login(self, username: str, password: str) -> AuthContext:
        user = self._users.by_username(username.strip().casefold())
        if user is None or not verify_password(password, user.password_hash):
            raise InvalidCredentialsError
        token = self._token_factory()
        _ = self._sessions.create(user.id, token, self._clock() + timedelta(hours=12))
        return AuthContext(UserView(UserId(user.id), user.username, user.full_name), token)

    def authenticate(self, raw_session: str) -> AuthContext | None:
        persisted = self._sessions.active(raw_session, self._clock())
        if persisted is None:
            return None
        user = persisted.user
        return AuthContext(UserView(UserId(user.id), user.username, user.full_name), raw_session)

    def logout(self, raw_session: str) -> None:
        self._sessions.delete(raw_session)
