from typing import final

from sqlalchemy import select
from sqlalchemy.orm import Session

from book_catalog.models.user import User


@final
class UserRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def by_username(self, username: str) -> User | None:
        return self._session.scalar(select(User).where(User.username == username))

    def get(self, user_id: int) -> User | None:
        return self._session.get(User, user_id)
