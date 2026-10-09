from collections.abc import AsyncGenerator, Awaitable, Callable
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Final

from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.responses import PlainTextResponse
from fastapi.staticfiles import StaticFiles

from book_catalog.database import initialize_database
from book_catalog.routers import auth, books, home, loans
from book_catalog.web import PACKAGE_ROOT

VM_PROOF: Final = Path("/run/folio-vm-proof")


@asynccontextmanager
async def lifespan(_application: FastAPI) -> AsyncGenerator[None]:
    initialize_database()
    yield


def create_app() -> FastAPI:
    application = FastAPI(title="Folio lending library", lifespan=lifespan)
    application.mount(
        "/static", StaticFiles(directory=PACKAGE_ROOT / "static", check_dir=False), name="static"
    )
    application.include_router(auth.router)
    application.include_router(home.router)
    application.include_router(books.router)
    application.include_router(loans.router)

    @application.get("/__vm-proof", response_class=PlainTextResponse, include_in_schema=False)
    def vm_proof() -> PlainTextResponse:
        if not VM_PROOF.is_file():
            raise HTTPException(status.HTTP_404_NOT_FOUND)
        return PlainTextResponse(VM_PROOF.read_text())

    @application.middleware("http")
    async def security_headers(
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; "
            "base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
        )
        response.headers["Referrer-Policy"] = "same-origin"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    return application


app = create_app()
