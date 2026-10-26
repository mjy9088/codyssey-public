from dataclasses import dataclass
from typing import TypedDict

from fastapi import Request, status
from fastapi.responses import HTMLResponse

from book_catalog.schemas.domain import BookView
from book_catalog.security import protected_context
from book_catalog.services.auth import AuthContext
from book_catalog.web import templates


class BookFormValues(TypedDict):
    title: str
    author: str
    year: str
    total_copies: str


@dataclass(frozen=True, slots=True)
class BookListPage:
    books: tuple[BookView, ...]
    query: str


@dataclass(frozen=True, slots=True)
class BookFormPage:
    book_id: int | None = None
    error: str | None = None
    values: BookFormValues | None = None
    response_status: int = status.HTTP_200_OK


@dataclass(frozen=True, slots=True)
class BookDetailPage:
    book: BookView
    error: str | None = None
    response_status: int = status.HTTP_200_OK


def render_book_list(
    request: Request,
    auth: AuthContext,
    page: BookListPage,
) -> HTMLResponse:
    context = {**protected_context(request, auth), "books": page.books, "query": page.query}
    return templates.TemplateResponse(request, "books.html", context)


def render_book_form(
    request: Request,
    auth: AuthContext,
    page: BookFormPage | None = None,
) -> HTMLResponse:
    actual_page = BookFormPage() if page is None else page
    context = {
        **protected_context(request, auth),
        "book_id": actual_page.book_id,
        "error": actual_page.error,
        "values": actual_page.values,
    }
    return templates.TemplateResponse(
        request, "book-form.html", context, status_code=actual_page.response_status
    )


def render_book_edit(request: Request, auth: AuthContext, book: BookView) -> HTMLResponse:
    context = {**protected_context(request, auth), "book": book}
    return templates.TemplateResponse(request, "book-form.html", context)


def render_book_detail(
    request: Request,
    auth: AuthContext,
    page: BookDetailPage,
) -> HTMLResponse:
    context = {**protected_context(request, auth), "book": page.book, "error": page.error}
    return templates.TemplateResponse(
        request, "book-detail.html", context, status_code=page.response_status
    )


def render_book_missing(request: Request, auth: AuthContext) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "404.html",
        {**protected_context(request, auth)},
        status_code=status.HTTP_404_NOT_FOUND,
    )
