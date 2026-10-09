from pathlib import Path
from typing import Final

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, PlainTextResponse

from book_catalog.web import templates

router = APIRouter()
VM_PROOF_PATH: Final = Path("/run/folio-vm-proof")


@router.get("/", response_class=HTMLResponse)
def home(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "home.html", {"page_title": "Home"})


@router.get("/showcase", response_class=HTMLResponse, include_in_schema=False)
def showcase(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "showcase.html", {"page_title": "UI showcase"})


@router.get("/__vm-proof", response_class=PlainTextResponse, include_in_schema=False)
def vm_proof() -> PlainTextResponse:
    if not VM_PROOF_PATH.is_file():
        return PlainTextResponse(status_code=404)
    return PlainTextResponse(VM_PROOF_PATH.read_text())
