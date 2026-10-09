from fastapi import FastAPI

from book_catalog.main import create_app


def test_application_constructs_with_crud_routes() -> None:
    app = create_app()

    assert isinstance(app, FastAPI)
    assert str(app.url_path_for("home")) == "/"
    assert str(app.url_path_for("list_books")) == "/books"
    assert str(app.url_path_for("book_detail", book_id="7")) == "/books/7"
