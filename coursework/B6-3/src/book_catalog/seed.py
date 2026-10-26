from typing import Final

from sqlalchemy import select
from sqlalchemy.orm import Session

from book_catalog.auth.passwords import hash_password
from book_catalog.models import Book, User

DEMO_PASSWORD: Final = "correct-horse-battery-staple"  # noqa: S105


def seed_database(session: Session) -> None:
    if session.scalar(select(User.id).limit(1)) is None:
        session.add(
            User(
                username="reader",
                full_name="Demo Reader",
                password_hash=hash_password(DEMO_PASSWORD),
            )
        )
    if session.scalar(select(Book.id).limit(1)) is None:
        session.add_all(
            [
                Book(title="Kindred", author="Octavia Butler", year=1979, total_copies=2),
                Book(
                    title="The Dispossessed",
                    author="Ursula Le Guin",
                    year=1974,
                    total_copies=1,
                ),
                Book(title="Piranesi", author="Susanna Clarke", year=2020, total_copies=3),
            ]
        )
    session.commit()
