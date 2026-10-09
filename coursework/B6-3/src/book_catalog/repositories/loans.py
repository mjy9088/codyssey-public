from datetime import datetime
from typing import final

from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from book_catalog.models.loan import Loan, LoanStatus


@final
class LoanRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def list_for_user(self, user_id: int, status: str | None) -> tuple[Loan, ...]:
        statement = (
            select(Loan)
            .options(joinedload(Loan.book), joinedload(Loan.user))
            .where(Loan.user_id == user_id)
            .order_by(Loan.borrowed_at.desc(), Loan.id.desc())
        )
        if status:
            statement = statement.where(Loan.status == status)
        return tuple(self._session.scalars(statement).all())

    def active_for_book(self, user_id: int, book_id: int) -> Loan | None:
        return self._session.scalar(
            select(Loan).where(
                Loan.user_id == user_id,
                Loan.book_id == book_id,
                Loan.status == LoanStatus.BORROWED,
            )
        )

    def get(self, loan_id: int) -> Loan | None:
        return self._session.scalar(
            select(Loan)
            .options(joinedload(Loan.book), joinedload(Loan.user))
            .where(Loan.id == loan_id)
        )

    def create(self, user_id: int, book_id: int, now: datetime) -> Loan:
        loan = Loan(user_id=user_id, book_id=book_id, borrowed_at=now)
        self._session.add(loan)
        self._session.commit()
        self._session.refresh(loan)
        return loan

    def mark_returned(self, loan: Loan, now: datetime) -> Loan:
        loan.status = LoanStatus.RETURNED
        loan.returned_at = now
        self._session.commit()
        self._session.refresh(loan)
        return loan
