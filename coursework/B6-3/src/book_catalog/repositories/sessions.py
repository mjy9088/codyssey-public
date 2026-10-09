from datetime import datetime
from hashlib import sha256
from typing import final

from sqlalchemy import delete, select
from sqlalchemy.orm import Session, joinedload

from book_catalog.models.session import ServerSession


def token_digest(raw: str) -> str:
    return sha256(raw.encode()).hexdigest()


@final
class SessionRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def create(self, user_id: int, raw_token: str, expires_at: datetime) -> ServerSession:
        persisted = ServerSession(
            user_id=user_id, token_digest=token_digest(raw_token), expires_at=expires_at
        )
        self._session.add(persisted)
        self._session.commit()
        self._session.refresh(persisted)
        return persisted

    def active(self, raw_token: str, now: datetime) -> ServerSession | None:
        statement = (
            select(ServerSession)
            .options(joinedload(ServerSession.user))
            .where(
                ServerSession.token_digest == token_digest(raw_token),
                ServerSession.expires_at > now,
            )
        )
        return self._session.scalar(statement)

    def delete(self, raw_token: str) -> None:
        _ = self._session.execute(
            delete(ServerSession).where(ServerSession.token_digest == token_digest(raw_token))
        )
        self._session.commit()
