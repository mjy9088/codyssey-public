from typing import Annotated, assert_never

from fastapi import APIRouter, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from book_catalog.presentation.books import (
    BookFormPage,
    render_book_detail,
    render_book_form,
    render_book_list,
    render_book_missing,
    render_csrf_failure,
    render_delete_confirmation,
)
from book_catalog.schemas.books import BookInput, InvalidBookInput
from book_catalog.security import verify_token
from book_catalog.services.books import BookNotFoundError
from book_catalog.web import BookServiceDep

router = APIRouter(prefix="/books")
FormText = Annotated[str, Form()]


@router.get("", response_class=HTMLResponse)
def list_books(request: Request, service: BookServiceDep, q: str = "") -> HTMLResponse:
    return render_book_list(request, service.list(q), q)


@router.get("/new", response_class=HTMLResponse)
def new_book(request: Request) -> HTMLResponse:
    return render_book_form(
        request,
        BookFormPage(None, "/books", "Add a book", "Add to catalog"),
    )


@router.post("", response_class=HTMLResponse)
def create_book(
    request: Request,
    service: BookServiceDep,
    title: FormText,
    author: FormText,
    year: FormText,
    csrf_token: FormText,
) -> Response:
    if not verify_token(csrf_token):
        return render_csrf_failure(request)
    parsed = BookInput.parse(title=title, author=author, year=year)
    match parsed:
        case InvalidBookInput():
            return render_book_form(
                request,
                BookFormPage(
                    parsed,
                    "/books",
                    "Add a book",
                    "Add to catalog",
                    status.HTTP_422_UNPROCESSABLE_CONTENT,
                ),
            )
        case BookInput():
            created = service.create(parsed)
        case unreachable:
            assert_never(unreachable)
    return RedirectResponse(
        f"/books/{created.id}?notice=created",
        status_code=status.HTTP_303_SEE_OTHER,
    )


@router.get("/{book_id}", response_class=HTMLResponse)
def book_detail(request: Request, book_id: int, service: BookServiceDep) -> HTMLResponse:
    try:
        book = service.get(book_id)
    except BookNotFoundError:
        return render_book_missing(request, book_id)
    return render_book_detail(request, book)


@router.get("/{book_id}/edit", response_class=HTMLResponse)
def edit_book(request: Request, book_id: int, service: BookServiceDep) -> HTMLResponse:
    try:
        book = service.get(book_id)
    except BookNotFoundError:
        return render_book_missing(request, book_id)
    return render_book_form(
        request,
        BookFormPage(
            BookInput(book.title, book.author, book.year),
            f"/books/{book_id}/edit",
            "Edit book",
            "Save changes",
        ),
    )


@router.post("/{book_id}/edit", response_class=HTMLResponse)
def update_book(
    request: Request,
    book_id: int,
    service: BookServiceDep,
    title: FormText,
    author: FormText,
    year: FormText,
    csrf_token: FormText,
) -> Response:
    if not verify_token(csrf_token):
        return render_csrf_failure(request)
    parsed = BookInput.parse(title=title, author=author, year=year)
    match parsed:
        case InvalidBookInput():
            return render_book_form(
                request,
                BookFormPage(
                    parsed,
                    f"/books/{book_id}/edit",
                    "Edit book",
                    "Save changes",
                    status.HTTP_422_UNPROCESSABLE_CONTENT,
                ),
            )
        case BookInput():
            draft = parsed
        case unreachable:
            assert_never(unreachable)
    try:
        updated = service.update(book_id, draft)
    except BookNotFoundError:
        return render_book_missing(request, book_id)
    return RedirectResponse(
        f"/books/{updated.id}?notice=updated",
        status_code=status.HTTP_303_SEE_OTHER,
    )


@router.get("/{book_id}/delete", response_class=HTMLResponse)
def confirm_delete(request: Request, book_id: int, service: BookServiceDep) -> HTMLResponse:
    try:
        book = service.get(book_id)
    except BookNotFoundError:
        return render_book_missing(request, book_id)
    return render_delete_confirmation(request, book)


@router.post("/{book_id}/delete", response_class=HTMLResponse)
def delete_book(
    request: Request,
    book_id: int,
    service: BookServiceDep,
    csrf_token: FormText,
) -> Response:
    if not verify_token(csrf_token):
        return render_csrf_failure(request)
    try:
        service.delete(book_id)
    except BookNotFoundError:
        return render_book_missing(request, book_id)
    return RedirectResponse("/books?notice=deleted", status_code=status.HTTP_303_SEE_OTHER)
