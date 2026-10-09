from __future__ import annotations

import datetime as dt
from typing import TYPE_CHECKING, ClassVar

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from book_catalog.models.base import Base

if TYPE_CHECKING:
    from book_catalog.models.user import User


class ServerSession(Base):
    """Opaque authenticated browser session stored only as a token digest."""

    __tablename__: ClassVar[str] = "server_sessions"

    id: Mapped[int] = mapped_column(primary_key=True, init=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_digest: Mapped[str] = mapped_column(String(64), unique=True, index=True, repr=False)
    expires_at: Mapped[dt.datetime]
    user: Mapped[User] = relationship(back_populates="sessions", init=False)
