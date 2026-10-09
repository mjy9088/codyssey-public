from typing import Annotated, assert_never

from fastapi import APIRouter, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from book_catalog.schemas.books import BookInput, InvalidBookInput
from book_catalog.security import issue_token, verify_token
from book_catalog.services.books import BookNotFoundError
from book_catalog.web import BookServiceDep, templates

router = APIRouter(prefix="/books")
FormText = Annotated[str, Form()]


def _missing(request: Request, book_id: int) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "not_found.html",
        {"page_title": "Book not found", "book_id": book_id},
        status_code=status.HTTP_404_NOT_FOUND,
    )


def _form_response(
    request: Request,
    *,
    values: BookInput | InvalidBookInput | None,
    action: str,
    heading: str,
    submit_label: str,
    response_status: int = status.HTTP_200_OK,
) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "book_form.html",
        {
            "page_title": heading,
            "values": values,
            "action": action,
            "heading": heading,
            "submit_label": submit_label,
            "csrf_token": issue_token(),
        },
        status_code=response_status,
    )


def _csrf_failure(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "csrf_error.html",
        {"page_title": "Request expired"},
        status_code=status.HTTP_403_FORBIDDEN,
    )


@router.get("", response_class=HTMLResponse)
def list_books(request: Request, service: BookServiceDep, q: str = "") -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "book_list.html",
        {
            "page_title": "Catalog",
            "books": service.list(q),
            "query": q,
            "notice": request.query_params.get("notice", ""),
        },
    )


@router.get("/new", response_class=HTMLResponse)
def new_book(request: Request) -> HTMLResponse:
    return _form_response(
        request,
        values=None,
        action="/books",
        heading="Add a book",
        submit_label="Add to catalog",
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
        return _csrf_failure(request)
    parsed = BookInput.parse(title=title, author=author, year=year)
    match parsed:
        case InvalidBookInput():
            return _form_response(
                request,
                values=parsed,
                action="/books",
                heading="Add a book",
                submit_label="Add to catalog",
                response_status=status.HTTP_422_UNPROCESSABLE_CONTENT,
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
        return _missing(request, book_id)
    return templates.TemplateResponse(
        request,
        "book_detail.html",
        {
            "page_title": book.title,
            "book": book,
            "notice": request.query_params.get("notice", ""),
        },
    )


@router.get("/{book_id}/edit", response_class=HTMLResponse)
def edit_book(request: Request, book_id: int, service: BookServiceDep) -> HTMLResponse:
    try:
        book = service.get(book_id)
    except BookNotFoundError:
        return _missing(request, book_id)
    return _form_response(
        request,
        values=BookInput(book.title, book.author, book.year),
        action=f"/books/{book_id}/edit",
        heading="Edit book",
        submit_label="Save changes",
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
        return _csrf_failure(request)
    parsed = BookInput.parse(title=title, author=author, year=year)
    match parsed:
        case InvalidBookInput():
            return _form_response(
                request,
                values=parsed,
                action=f"/books/{book_id}/edit",
                heading="Edit book",
                submit_label="Save changes",
                response_status=status.HTTP_422_UNPROCESSABLE_CONTENT,
            )
        case BookInput():
            draft = parsed
        case unreachable:
            assert_never(unreachable)
    try:
        updated = service.update(book_id, draft)
    except BookNotFoundError:
        return _missing(request, book_id)
    return RedirectResponse(
        f"/books/{updated.id}?notice=updated",
        status_code=status.HTTP_303_SEE_OTHER,
    )


@router.get("/{book_id}/delete", response_class=HTMLResponse)
def confirm_delete(request: Request, book_id: int, service: BookServiceDep) -> HTMLResponse:
    try:
        book = service.get(book_id)
    except BookNotFoundError:
        return _missing(request, book_id)
    return templates.TemplateResponse(
        request,
        "book_delete.html",
        {"page_title": "Remove book", "book": book, "csrf_token": issue_token()},
    )


@router.post("/{book_id}/delete", response_class=HTMLResponse)
def delete_book(
    request: Request,
    book_id: int,
    service: BookServiceDep,
    csrf_token: FormText,
) -> Response:
    if not verify_token(csrf_token):
        return _csrf_failure(request)
    try:
        service.delete(book_id)
    except BookNotFoundError:
        return _missing(request, book_id)
    return RedirectResponse("/books?notice=deleted", status_code=status.HTTP_303_SEE_OTHER)
