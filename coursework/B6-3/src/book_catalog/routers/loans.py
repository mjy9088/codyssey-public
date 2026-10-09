from typing import Annotated

from fastapi import APIRouter, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from book_catalog.services.loans import LoanRuleError
from book_catalog.web import AuthDep, LoanServiceDep, protected_context, require_csrf, templates

router = APIRouter()


@router.get("/loans", response_class=HTMLResponse)
def list_loans(
    request: Request,
    loans: LoanServiceDep,
    auth: AuthDep,
    loan_status: str = "all",
) -> HTMLResponse:
    context = protected_context(request, auth)
    context.update({"loans": loans.list(auth.user.id, loan_status), "loan_status": loan_status})
    return templates.TemplateResponse(request, "loans.html", context)


@router.post("/books/{book_id}/borrow")
def borrow_book(
    request: Request,
    book_id: int,
    loans: LoanServiceDep,
    auth: AuthDep,
    csrf_token: Annotated[str, Form()],
) -> Response:
    require_csrf(auth, csrf_token)
    try:
        _ = loans.borrow(auth.user.id, book_id)
    except LoanRuleError as error:
        context = protected_context(request, auth)
        context["error"] = str(error)
        return templates.TemplateResponse(
            request, "loan-error.html", context, status_code=status.HTTP_409_CONFLICT
        )
    return RedirectResponse("/loans?loan_status=borrowed", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/loans/{loan_id}/return")
def return_book(
    request: Request,
    loan_id: int,
    loans: LoanServiceDep,
    auth: AuthDep,
    csrf_token: Annotated[str, Form()],
) -> Response:
    require_csrf(auth, csrf_token)
    try:
        _ = loans.return_loan(auth.user.id, loan_id)
    except LoanRuleError as error:
        context = protected_context(request, auth)
        context["error"] = str(error)
        return templates.TemplateResponse(
            request, "loan-error.html", context, status_code=status.HTTP_409_CONFLICT
        )
    return RedirectResponse("/loans", status_code=status.HTTP_303_SEE_OTHER)
