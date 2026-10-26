from datetime import datetime

import pytest
from fastapi import Request
from fastapi.routing import APIRoute
from sqlalchemy.orm import Session

from book_catalog.auth.csrf import issue_public_token
from book_catalog.auth.passwords import hash_password
from book_catalog.main import create_app
from book_catalog.models.user import User
from book_catalog.repositories.sessions import SessionRepository
from book_catalog.repositories.users import UserRepository
from book_catalog.routers import auth, books, home, loans
from book_catalog.security import require_auth
from book_catalog.services.auth import AuthService


def test_application_imports_with_all_expected_routes() -> None:
    application = create_app()

    assert application.title == "Folio lending library"


def test_route_inventory_marks_every_core_route_as_protected() -> None:
    # Given
    routes = (*auth.router.routes, *home.router.routes, *books.router.routes, *loans.router.routes)
    expected_protected = {
        ("GET", "/"),
        ("GET", "/showcase"),
        ("GET", "/books"),
        ("GET", "/books/new"),
        ("POST", "/books"),
        ("GET", "/books/{book_id}"),
        ("GET", "/books/{book_id}/edit"),
        ("POST", "/books/{book_id}"),
        ("POST", "/books/{book_id}/delete"),
        ("GET", "/loans"),
        ("POST", "/books/{book_id}/borrow"),
        ("POST", "/loans/{loan_id}/return"),
        ("POST", "/logout"),
    }

    # When
    protected = {
        (method, route.path)
        for route in routes
        if isinstance(route, APIRoute)
        and any(dependency.call is require_auth for dependency in route.dependant.dependencies)
        for method in route.methods or set()
    }
    public_login = {
        (method, route.path)
        for route in routes
        if isinstance(route, APIRoute) and route.path == "/login"
        for method in route.methods or set()
    }

    # Then
    assert protected == expected_protected
    assert public_login == {("GET", "/login"), ("POST", "/login")}


def _request() -> Request:
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/login",
            "headers": [],
            "scheme": "http",
            "server": ("testserver", 80),
            "client": ("testclient", 50000),
            "query_string": b"",
            "root_path": "",
        }
    )


def _auth_service(db: Session, now: datetime) -> AuthService:
    user = db.query(User).one()
    user.password_hash = hash_password("secret")
    db.commit()
    return AuthService(
        UserRepository(db),
        SessionRepository(db),
        lambda: now,
        token_factory=lambda: "route-test-session",
    )


@pytest.mark.parametrize(
    "next_path", [r"/\attacker.example", "/\t/attacker.example", "//attacker.example"]
)
def test_login_route_rejects_browser_normalized_external_redirects(
    db: Session, fixed_now: datetime, next_path: str
) -> None:
    # Given / When
    response = auth.login(
        _request(),
        _auth_service(db, fixed_now),
        "reader",
        "secret",
        issue_public_token(),
        next_path,
    )

    # Then
    assert response.headers["location"] == "/"


def test_login_route_preserves_local_redirect_with_query(db: Session, fixed_now: datetime) -> None:
    # Given / When
    response = auth.login(
        _request(),
        _auth_service(db, fixed_now),
        "reader",
        "secret",
        issue_public_token(),
        "/books?q=kindred",
    )

    # Then
    assert response.headers["location"] == "/books?q=kindred"
