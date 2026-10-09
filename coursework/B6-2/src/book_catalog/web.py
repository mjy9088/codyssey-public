from pathlib import Path
from typing import Annotated, Final

from fastapi import Depends
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from book_catalog.database import get_session
from book_catalog.repositories.books import BookRepository
from book_catalog.services.books import BookService

PACKAGE_ROOT: Final = Path(__file__).parent
templates: Final = Jinja2Templates(directory=PACKAGE_ROOT / "templates")


def get_book_service(session: Annotated[Session, Depends(get_session)]) -> BookService:
    return BookService(BookRepository(session))


BookServiceDep = Annotated[BookService, Depends(get_book_service)]
