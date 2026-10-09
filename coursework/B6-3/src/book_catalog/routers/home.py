from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from book_catalog.web import AuthDep, BookServiceDep, protected_context, templates

router = APIRouter()


@router.get("/showcase", response_class=HTMLResponse)
def showcase(request: Request, auth: AuthDep) -> HTMLResponse:
    return templates.TemplateResponse(request, "showcase.html", protected_context(request, auth))


@router.get("/", response_class=HTMLResponse)
def home(request: Request, books: BookServiceDep, auth: AuthDep) -> HTMLResponse:
    context = protected_context(request, auth)
    context["books"] = books.list()
    return templates.TemplateResponse(request, "index.html", context)
