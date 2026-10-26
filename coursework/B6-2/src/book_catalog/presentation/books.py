from dataclasses import dataclass

from fastapi import Request, status
from fastapi.responses import HTMLResponse

from book_catalog.schemas.books import BookInput, BookView, InvalidBookInput
from book_catalog.security import issue_token
from book_catalog.web import templates


@dataclass(frozen=True, slots=True)
class BookFormPage:
    values: BookInput | InvalidBookInput | None
    action: str
    heading: str
    submit_label: str
    response_status: int = status.HTTP_200_OK


def render_book_missing(request: Request, book_id: int) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "not_found.html",
        {"page_title": "Book not found", "book_id": book_id},
        status_code=status.HTTP_404_NOT_FOUND,
    )


def render_book_form(
    request: Request,
    page: BookFormPage,
) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "book_form.html",
        {
            "page_title": page.heading,
            "values": page.values,
            "action": page.action,
            "heading": page.heading,
            "submit_label": page.submit_label,
            "csrf_token": issue_token(),
        },
        status_code=page.response_status,
    )


def render_csrf_failure(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "csrf_error.html",
        {"page_title": "Request expired"},
        status_code=status.HTTP_403_FORBIDDEN,
    )


def render_book_list(
    request: Request,
    books: tuple[BookView, ...],
    query: str,
) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "book_list.html",
        {
            "page_title": "Catalog",
            "books": books,
            "query": query,
            "notice": request.query_params.get("notice", ""),
        },
    )


def render_book_detail(request: Request, book: BookView) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "book_detail.html",
        {
            "page_title": book.title,
            "book": book,
            "notice": request.query_params.get("notice", ""),
        },
    )


def render_delete_confirmation(request: Request, book: BookView) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "book_delete.html",
        {"page_title": "Remove book", "book": book, "csrf_token": issue_token()},
    )
