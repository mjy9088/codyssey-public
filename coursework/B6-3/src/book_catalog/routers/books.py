from typing import Annotated, TypedDict

from fastapi import APIRouter, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from book_catalog.schemas.domain import BookInput
from book_catalog.services.books import (
    BookHasLoansError,
    BookInventoryConflictError,
    BookNotFoundError,
)
from book_catalog.web import AuthDep, BookServiceDep, protected_context, require_csrf, templates

router = APIRouter(prefix="/books")


class BookFormValues(TypedDict):
    title: str
    author: str
    year: str
    total_copies: str


def render_form(
    request: Request,
    auth: AuthDep,
    book_id: int | None = None,
    error: str | None = None,
    *,
    values: BookFormValues | None = None,
) -> HTMLResponse:
    context = protected_context(request, auth)
    context.update({"book_id": book_id, "error": error, "values": values})
    return templates.TemplateResponse(request, "book-form.html", context)


@router.get("", response_class=HTMLResponse)
def list_books(request: Request, books: BookServiceDep, auth: AuthDep, q: str = "") -> HTMLResponse:
    context = protected_context(request, auth)
    context.update({"books": books.list(q), "query": q})
    return templates.TemplateResponse(request, "books.html", context)


@router.get("/new", response_class=HTMLResponse)
def new_book(request: Request, auth: AuthDep) -> HTMLResponse:
    return render_form(request, auth)


@router.post("")
def create_book(
    request: Request,
    books: BookServiceDep,
    auth: AuthDep,
    title: Annotated[str, Form()],
    author: Annotated[str, Form()],
    year: Annotated[str, Form()],
    total_copies: Annotated[str, Form()],
    csrf_token: Annotated[str, Form()],
) -> Response:
    require_csrf(auth, csrf_token)
    draft = BookInput.parse(title, author, year, total_copies)
    if draft is None:
        return render_form(
            request,
            auth,
            error="Enter valid book details",
            values=BookFormValues(title=title, author=author, year=year, total_copies=total_copies),
        )
    created = books.create(draft)
    return RedirectResponse(f"/books/{created.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/{book_id}", response_class=HTMLResponse)
def book_detail(
    request: Request, book_id: int, books: BookServiceDep, auth: AuthDep
) -> HTMLResponse:
    try:
        book = books.get(book_id)
    except BookNotFoundError:
        return templates.TemplateResponse(
            request,
            "404.html",
            protected_context(request, auth),
            status_code=status.HTTP_404_NOT_FOUND,
        )
    context = protected_context(request, auth)
    context["book"] = book
    return templates.TemplateResponse(request, "book-detail.html", context)


@router.get("/{book_id}/edit", response_class=HTMLResponse)
def edit_book(request: Request, book_id: int, books: BookServiceDep, auth: AuthDep) -> HTMLResponse:
    try:
        book = books.get(book_id)
    except BookNotFoundError:
        return templates.TemplateResponse(
            request,
            "404.html",
            protected_context(request, auth),
            status_code=status.HTTP_404_NOT_FOUND,
        )
    context = protected_context(request, auth)
    context["book"] = book
    return templates.TemplateResponse(request, "book-form.html", context)


@router.post("/{book_id}")
def update_book(
    request: Request,
    book_id: int,
    books: BookServiceDep,
    auth: AuthDep,
    title: Annotated[str, Form()],
    author: Annotated[str, Form()],
    year: Annotated[str, Form()],
    total_copies: Annotated[str, Form()],
    csrf_token: Annotated[str, Form()],
) -> Response:
    require_csrf(auth, csrf_token)
    draft = BookInput.parse(title, author, year, total_copies)
    if draft is None:
        return render_form(
            request,
            auth,
            book_id,
            "Enter valid book details",
            values=BookFormValues(title=title, author=author, year=year, total_copies=total_copies),
        )
    try:
        _ = books.update(book_id, draft)
    except BookInventoryConflictError as error:
        response = render_form(
            request,
            auth,
            book_id,
            str(error),
            values=BookFormValues(
                title=title,
                author=author,
                year=year,
                total_copies=total_copies,
            ),
        )
        response.status_code = status.HTTP_409_CONFLICT
        return response
    except BookNotFoundError:
        return templates.TemplateResponse(
            request,
            "404.html",
            protected_context(request, auth),
            status_code=status.HTTP_404_NOT_FOUND,
        )
    return RedirectResponse(f"/books/{book_id}", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/{book_id}/delete")
def delete_book(
    request: Request,
    book_id: int,
    books: BookServiceDep,
    auth: AuthDep,
    csrf_token: Annotated[str, Form()],
) -> Response:
    require_csrf(auth, csrf_token)
    try:
        books.delete(book_id)
    except BookHasLoansError as error:
        context = protected_context(request, auth)
        context.update({"book": books.get(book_id), "error": str(error)})
        return templates.TemplateResponse(
            request, "book-detail.html", context, status_code=status.HTTP_409_CONFLICT
        )
    except BookNotFoundError:
        return templates.TemplateResponse(
            request,
            "404.html",
            protected_context(request, auth),
            status_code=status.HTTP_404_NOT_FOUND,
        )
    return RedirectResponse("/books", status_code=status.HTTP_303_SEE_OTHER)
