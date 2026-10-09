from collections.abc import AsyncGenerator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.staticfiles import StaticFiles

from book_catalog.database import initialize_database
from book_catalog.routers import books, home
from book_catalog.web import PACKAGE_ROOT


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None]:
    initialize_database()
    yield


def create_app() -> FastAPI:
    application = FastAPI(title="Folio book catalog", lifespan=lifespan)
    application.mount("/static", StaticFiles(directory=PACKAGE_ROOT / "static"), name="static")
    application.include_router(home.router)
    application.include_router(books.router)

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
