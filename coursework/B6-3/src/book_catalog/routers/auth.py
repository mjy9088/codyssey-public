from typing import Annotated

from fastapi import APIRouter, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from book_catalog.auth.csrf import issue_public_token, verify_public_token
from book_catalog.services.auth import InvalidCredentialsError
from book_catalog.web import SESSION_COOKIE, AuthDep, AuthServiceDep, require_csrf, templates

router = APIRouter()


@router.get("/login", response_class=HTMLResponse)
def login_form(request: Request, next_path: str = "/") -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "login.html",
        {"csrf_token": issue_public_token(), "next_path": next_path},
    )


@router.post("/login", response_class=HTMLResponse)
def login(
    request: Request,
    service: AuthServiceDep,
    username: Annotated[str, Form()],
    password: Annotated[str, Form()],
    csrf_token: Annotated[str, Form()],
    next_path: Annotated[str, Form()] = "/",
) -> Response:
    if not verify_public_token(csrf_token):
        return templates.TemplateResponse(
            request,
            "login.html",
            {"csrf_token": issue_public_token(), "next_path": "/", "error": "Form expired"},
            status_code=status.HTTP_403_FORBIDDEN,
        )
    try:
        auth = service.login(username, password)
    except InvalidCredentialsError as error:
        return templates.TemplateResponse(
            request,
            "login.html",
            {"csrf_token": issue_public_token(), "next_path": next_path, "error": str(error)},
            status_code=status.HTTP_401_UNAUTHORIZED,
        )
    destination = next_path if next_path.startswith("/") and not next_path.startswith("//") else "/"
    response = RedirectResponse(destination, status_code=status.HTTP_303_SEE_OTHER)
    response.set_cookie(
        SESSION_COOKIE,
        auth.raw_session,
        httponly=True,
        max_age=60 * 60 * 12,
        samesite="strict",
    )
    return response


@router.post("/logout")
def logout(
    service: AuthServiceDep,
    auth: AuthDep,
    csrf_token: Annotated[str, Form()],
) -> RedirectResponse:
    require_csrf(auth, csrf_token)
    service.logout(auth.raw_session)
    response = RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)
    response.delete_cookie(SESSION_COOKIE)
    return response
