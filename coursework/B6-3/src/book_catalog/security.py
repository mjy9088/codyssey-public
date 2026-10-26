from typing import Annotated, Final, TypedDict

from fastapi import Cookie, Depends, HTTPException, Request, status

from book_catalog.auth.csrf import session_token, verify_session_token
from book_catalog.dependencies import get_auth_service
from book_catalog.schemas.domain import UserView
from book_catalog.services.auth import AuthContext, AuthService

SESSION_COOKIE: Final = "folio_session"


class ProtectedContext(TypedDict):
    request: Request
    user: UserView
    csrf_token: str


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


AuthDep = Annotated[AuthContext, Depends(require_auth)]


def protected_context(request: Request, auth: AuthContext) -> ProtectedContext:
    return ProtectedContext(
        request=request,
        user=auth.user,
        csrf_token=session_token(auth.raw_session),
    )
