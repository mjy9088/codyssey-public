from typing import Annotated

from fastapi import APIRouter, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from book_catalog.dependencies import BookServiceDep
from book_catalog.presentation.books import (
    BookDetailPage,
    BookFormPage,
    BookFormValues,
    BookListPage,
    render_book_detail,
    render_book_edit,
    render_book_form,
    render_book_list,
    render_book_missing,
)
from book_catalog.schemas.domain import BookInput
from book_catalog.security import AuthDep, require_csrf
from book_catalog.services.books import (
    BookHasLoansError,
    BookInventoryConflictError,
    BookNotFoundError,
)

router = APIRouter(prefix="/books")


@router.get("", response_class=HTMLResponse)
def list_books(request: Request, books: BookServiceDep, auth: AuthDep, q: str = "") -> HTMLResponse:
    return render_book_list(request, auth, BookListPage(books.list(q), q))


@router.get("/new", response_class=HTMLResponse)
def new_book(request: Request, auth: AuthDep) -> HTMLResponse:
    return render_book_form(request, auth)


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
        return render_book_form(
            request,
            auth,
            BookFormPage(
                error="Enter valid book details",
                values=BookFormValues(
                    title=title,
                    author=author,
                    year=year,
                    total_copies=total_copies,
                ),
            ),
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
        return render_book_missing(request, auth)
    return render_book_detail(request, auth, BookDetailPage(book))


@router.get("/{book_id}/edit", response_class=HTMLResponse)
def edit_book(request: Request, book_id: int, books: BookServiceDep, auth: AuthDep) -> HTMLResponse:
    try:
        book = books.get(book_id)
    except BookNotFoundError:
        return render_book_missing(request, auth)
    return render_book_edit(request, auth, book)


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
        return render_book_form(
            request,
            auth,
            BookFormPage(
                book_id=book_id,
                error="Enter valid book details",
                values=BookFormValues(
                    title=title,
                    author=author,
                    year=year,
                    total_copies=total_copies,
                ),
            ),
        )
    try:
        _ = books.update(book_id, draft)
    except BookInventoryConflictError as error:
        return render_book_form(
            request,
            auth,
            BookFormPage(
                book_id=book_id,
                error=str(error),
                values=BookFormValues(
                    title=title,
                    author=author,
                    year=year,
                    total_copies=total_copies,
                ),
                response_status=status.HTTP_409_CONFLICT,
            ),
        )
    except BookNotFoundError:
        return render_book_missing(request, auth)
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
        return render_book_detail(
            request,
            auth,
            BookDetailPage(
                books.get(book_id),
                error=str(error),
                response_status=status.HTTP_409_CONFLICT,
            ),
        )
    except BookNotFoundError:
        return render_book_missing(request, auth)
    return RedirectResponse("/books", status_code=status.HTTP_303_SEE_OTHER)
