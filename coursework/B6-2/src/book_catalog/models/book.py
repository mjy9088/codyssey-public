from typing import ClassVar

from sqlalchemy import CheckConstraint, String
from sqlalchemy.orm import Mapped, mapped_column

from book_catalog.models.base import Base


class Book(Base):
    """A mutable ORM entity whose lifecycle is owned by a Session."""

    __tablename__: ClassVar[str] = "books"
    __table_args__: ClassVar[tuple[CheckConstraint, ...]] = (
        CheckConstraint("length(trim(title)) > 0", name="book_title_present"),
        CheckConstraint("length(trim(author)) > 0", name="book_author_present"),
        CheckConstraint("year BETWEEN 1450 AND 2100", name="book_year_range"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, init=False)
    title: Mapped[str] = mapped_column(String(160), index=True)
    author: Mapped[str] = mapped_column(String(120), index=True)
    year: Mapped[int]
