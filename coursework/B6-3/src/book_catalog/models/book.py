from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from sqlalchemy import CheckConstraint, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from book_catalog.models.base import Base

if TYPE_CHECKING:
    from book_catalog.models.loan import Loan


class Book(Base):
    """Catalog title with finite lendable inventory."""

    __tablename__: ClassVar[str] = "books"
    __table_args__: ClassVar[tuple[CheckConstraint, ...]] = (
        CheckConstraint("length(trim(title)) > 0", name="book_title_present"),
        CheckConstraint("length(trim(author)) > 0", name="book_author_present"),
        CheckConstraint("year BETWEEN 1450 AND 2100", name="book_year_range"),
        CheckConstraint("total_copies > 0", name="book_total_copies_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, init=False)
    title: Mapped[str] = mapped_column(String(160), index=True)
    author: Mapped[str] = mapped_column(String(120), index=True)
    year: Mapped[int]
    total_copies: Mapped[int] = mapped_column(default=1)
    # Loan history is retained with its book; catalog deletion is rejected while loans exist.
    loans: Mapped[list[Loan]] = relationship(back_populates="book", default_factory=list)
