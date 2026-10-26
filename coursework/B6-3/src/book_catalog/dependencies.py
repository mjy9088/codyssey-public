from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends
from sqlalchemy.orm import Session

from book_catalog.database import get_session
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.repositories.sessions import SessionRepository
from book_catalog.repositories.users import UserRepository
from book_catalog.services.auth import AuthService
from book_catalog.services.books import BookService
from book_catalog.services.loan_views import LoanReadService
from book_catalog.services.loans import LoanService


def now() -> datetime:
    return datetime.now(UTC)


def get_auth_service(session: Annotated[Session, Depends(get_session)]) -> AuthService:
    return AuthService(UserRepository(session), SessionRepository(session), now)


def get_book_service(session: Annotated[Session, Depends(get_session)]) -> BookService:
    return BookService(BookRepository(session))


def get_loan_service(session: Annotated[Session, Depends(get_session)]) -> LoanService:
    return LoanService(LoanRepository(session), BookRepository(session), now)


def get_loan_read_service(session: Annotated[Session, Depends(get_session)]) -> LoanReadService:
    return LoanReadService(LoanRepository(session), BookRepository(session))


AuthServiceDep = Annotated[AuthService, Depends(get_auth_service)]
BookServiceDep = Annotated[BookService, Depends(get_book_service)]
LoanServiceDep = Annotated[LoanService, Depends(get_loan_service)]
LoanReadServiceDep = Annotated[LoanReadService, Depends(get_loan_read_service)]
