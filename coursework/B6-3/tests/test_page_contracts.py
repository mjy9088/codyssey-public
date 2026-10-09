from collections.abc import Callable, Iterator
from datetime import datetime
from pathlib import Path
from urllib.parse import urlencode

import anyio
import pytest
from fastapi import Request
from fastapi.responses import HTMLResponse
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session
from starlette.types import Message, Scope

from book_catalog.auth.csrf import session_token
from book_catalog.database import get_session
from book_catalog.main import create_app
from book_catalog.models import Base
from book_catalog.models.book import Book
from book_catalog.models.loan import Loan
from book_catalog.models.user import User
from book_catalog.repositories.books import BookRepository
from book_catalog.routers import books, home
from book_catalog.schemas.domain import UserId, UserView
from book_catalog.services.auth import AuthContext
from book_catalog.services.books import BookService
from book_catalog.web import require_auth


@pytest.fixture
def page_context() -> tuple[Request, AuthContext]:
    request = Request(
        {
            "type": "http",
            "method": "GET",
            "scheme": "http",
            "server": ("testserver", 80),
            "path": "/books",
            "headers": [],
            "router": create_app().router,
        }
    )
    auth = AuthContext(UserView(UserId(1), "reader", "Demo Reader"), "test-session")
    return request, auth


@pytest.mark.parametrize("editing", [False, True])
def test_invalid_submission_retains_fields(
    db: Session, page_context: tuple[Request, AuthContext], *, editing: bool
) -> None:
    # Given
    request, auth = page_context
    service = BookService(BookRepository(db))
    token = session_token(auth.raw_session)

    # When
    if editing:
        response = books.update_book(
            request, 1, service, auth, "Retained title", "Retained author", "1400", "2", token
        )
    else:
        response = books.create_book(
            request, service, auth, "Retained title", "Retained author", "1400", "2", token
        )

    # Then
    body = bytes(response.body).decode()
    assert 'name="title" value="Retained title"' in body
    assert 'name="author" value="Retained author"' in body
    assert 'value="1400"' in body
    assert 'value="2"' in body
    assert f'action="{"/books/1" if editing else "/books"}"' in body


@pytest.mark.parametrize("handler", [books.book_detail, books.edit_book])
def test_missing_book_retains_authenticated_navigation(
    db: Session,
    page_context: tuple[Request, AuthContext],
    handler: Callable[[Request, int, BookService, AuthContext], HTMLResponse],
) -> None:
    # Given
    request, auth = page_context

    # When
    response = handler(request, 999, BookService(BookRepository(db)), auth)

    # Then
    assert response.status_code == 404
    assert 'action="/logout"' in bytes(response.body).decode()
    assert session_token(auth.raw_session) in bytes(response.body).decode()


def test_showcase_renders_member_controls(page_context: tuple[Request, AuthContext]) -> None:
    # Given
    request, auth = page_context

    # When
    response = home.showcase(request, auth)

    # Then
    assert response.status_code == 200
    assert 'action="/logout"' in bytes(response.body).decode()


def test_edit_retains_values_and_inventory_when_active_loans_exceed_request(
    tmp_path: Path, fixed_now: datetime
) -> None:
    # Given
    engine: Engine = create_engine(f"sqlite+pysqlite:///{tmp_path / 'page-contract.db'}")
    Base.metadata.create_all(engine)
    with Session(engine, expire_on_commit=False) as setup_db:
        first_user = User("reader", "Demo Reader", "unused")
        second_user = User("second-reader", "Second Reader", "unused")
        book = Book(title="Kindred", author="Octavia Butler", year=1979, total_copies=2)
        setup_db.add_all([first_user, second_user, book])
        setup_db.flush()
        setup_db.add_all(
            [
                Loan(user_id=first_user.id, book_id=book.id, borrowed_at=fixed_now),
                Loan(user_id=second_user.id, book_id=book.id, borrowed_at=fixed_now),
            ]
        )
        setup_db.commit()
        book_id = book.id
        first_user_id = first_user.id

    auth = AuthContext(UserView(UserId(first_user_id), "reader", "Demo Reader"), "test-session")
    app = create_app()

    def request_session() -> Iterator[Session]:
        with Session(engine, expire_on_commit=False) as session:
            yield session

    app.dependency_overrides[get_session] = request_session
    app.dependency_overrides[require_auth] = lambda: auth
    form_body = urlencode(
        {
            "title": "Retained title",
            "author": "Retained author",
            "year": "2024",
            "total_copies": "1",
            "csrf_token": session_token(auth.raw_session),
        }
    ).encode()

    async def post_edit() -> tuple[int, bytes]:
        messages: list[Message] = []
        request_sent = False

        async def receive() -> Message:
            nonlocal request_sent
            if request_sent:
                return {"type": "http.disconnect"}
            request_sent = True
            return {"type": "http.request", "body": form_body, "more_body": False}

        async def send(message: Message) -> None:
            messages.append(message)

        scope: Scope = {
            "type": "http",
            "asgi": {"version": "3.0", "spec_version": "2.3"},
            "http_version": "1.1",
            "method": "POST",
            "scheme": "http",
            "path": f"/books/{book_id}",
            "raw_path": f"/books/{book_id}".encode(),
            "query_string": b"",
            "root_path": "",
            "headers": [
                (b"host", b"testserver"),
                (b"content-type", b"application/x-www-form-urlencoded"),
                (b"content-length", str(len(form_body)).encode()),
            ],
            "client": ("testclient", 50000),
            "server": ("testserver", 80),
            "state": {},
        }
        await app(scope, receive, send)
        assert messages[0]["type"] == "http.response.start"
        body = b"".join(message.get("body", b"") for message in messages[1:])
        return messages[0]["status"], body

    # When
    status_code, response_body = anyio.run(post_edit)

    # Then
    body = response_body.decode()
    assert status_code == 409
    assert 'name="title" value="Retained title"' in body
    assert 'name="author" value="Retained author"' in body
    assert 'name="total_copies" type="number" min="1" value="1"' in body
    with Session(engine) as verification_db:
        persisted = verification_db.get(Book, book_id)
        assert persisted is not None
        assert persisted.title == "Kindred"
        assert persisted.total_copies == 2
    engine.dispose()
