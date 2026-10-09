from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from sqlalchemy import CheckConstraint, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from book_catalog.models.base import Base

if TYPE_CHECKING:
    from book_catalog.models.loan import Loan
    from book_catalog.models.session import ServerSession


class User(Base):
    """Persisted member and owner of loans and authenticated sessions."""

    __tablename__: ClassVar[str] = "users"
    __table_args__: ClassVar[tuple[CheckConstraint, ...]] = (
        CheckConstraint("length(trim(username)) >= 3", name="username_present"),
        CheckConstraint("length(trim(full_name)) > 0", name="user_full_name_present"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, init=False)
    username: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(100))
    password_hash: Mapped[str] = mapped_column(String(256), repr=False)
    # Account deletion owns cleanup so dependent security and lending rows cannot become orphans.
    loans: Mapped[list[Loan]] = relationship(
        back_populates="user", cascade="all, delete-orphan", default_factory=list
    )
    sessions: Mapped[list[ServerSession]] = relationship(
        back_populates="user", cascade="all, delete-orphan", default_factory=list
    )
