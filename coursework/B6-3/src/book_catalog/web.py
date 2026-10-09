from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated, Final

from fastapi import Cookie, Depends, HTTPException, Request, status
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from book_catalog.auth.csrf import session_token, verify_session_token
from book_catalog.database import get_session
from book_catalog.repositories.books import BookRepository
from book_catalog.repositories.loans import LoanRepository
from book_catalog.repositories.sessions import SessionRepository
from book_catalog.repositories.users import UserRepository
from book_catalog.services.auth import AuthContext, AuthService
from book_catalog.services.books import BookService
from book_catalog.services.loans import LoanService

PACKAGE_ROOT: Final = Path(__file__).parent
SESSION_COOKIE: Final = "folio_session"
templates: Final = Jinja2Templates(directory=PACKAGE_ROOT / "templates")


def now() -> datetime:
    return datetime.now(UTC)


def get_auth_service(session: Annotated[Session, Depends(get_session)]) -> AuthService:
    return AuthService(UserRepository(session), SessionRepository(session), now)


def get_book_service(session: Annotated[Session, Depends(get_session)]) -> BookService:
    return BookService(BookRepository(session))


def get_loan_service(session: Annotated[Session, Depends(get_session)]) -> LoanService:
    return LoanService(LoanRepository(session), BookRepository(session), now)


def require_auth(
    request: Request,
    service: Annotated[AuthService, Depends(get_auth_service)],
    raw_session: Annotated[str | None, Cookie(alias=SESSION_COOKIE)] = None,
) -> AuthContext:
    context = None if raw_session is None else service.authenticate(raw_session)
    if context is None:
        raise HTTPException(
            status_code=status.HTTP_303_SEE_OTHER,
            headers={"Location": f"/login?next={request.url.path}"},
        )
    return context


def require_csrf(auth: AuthContext, csrf_token: str) -> None:
    if not verify_session_token(auth.raw_session, csrf_token):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid CSRF token")


AuthServiceDep = Annotated[AuthService, Depends(get_auth_service)]
BookServiceDep = Annotated[BookService, Depends(get_book_service)]
LoanServiceDep = Annotated[LoanService, Depends(get_loan_service)]
AuthDep = Annotated[AuthContext, Depends(require_auth)]


def protected_context(request: Request, auth: AuthContext) -> dict[str, Request | str | object]:
    return {
        "request": request,
        "user": auth.user,
        "csrf_token": session_token(auth.raw_session),
    }
