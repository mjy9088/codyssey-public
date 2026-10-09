from __future__ import annotations

import datetime as dt
from enum import StrEnum
from typing import TYPE_CHECKING, ClassVar

from sqlalchemy import CheckConstraint, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from book_catalog.models.base import Base

if TYPE_CHECKING:
    from book_catalog.models.book import Book
    from book_catalog.models.user import User


class LoanStatus(StrEnum):
    BORROWED = "borrowed"
    RETURNED = "returned"


class Loan(Base):
    """Ownership-scoped borrowing state transition."""

    __tablename__: ClassVar[str] = "loans"
    __table_args__: ClassVar[tuple[CheckConstraint | Index, ...]] = (
        CheckConstraint("status IN ('borrowed', 'returned')", name="loan_status_valid"),
        CheckConstraint(
            "status='borrowed'AND returned_at ISNULL OR status='returned'AND returned_at NOTNULL",
            name="loan_return_state_consistent",
        ),
        Index("ix_loans_book_status", "book_id", "status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, init=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    book_id: Mapped[int] = mapped_column(ForeignKey("books.id", ondelete="RESTRICT"), index=True)
    borrowed_at: Mapped[dt.datetime]
    status: Mapped[str] = mapped_column(String(12), default=LoanStatus.BORROWED)
    returned_at: Mapped[dt.datetime | None] = mapped_column(default=None)
    user: Mapped[User] = relationship(back_populates="loans", init=False)
    book: Mapped[Book] = relationship(back_populates="loans", init=False)
