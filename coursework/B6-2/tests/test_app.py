from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.routing import APIRoute

from book_catalog.database import get_session
from book_catalog.main import create_app
from book_catalog.routers import books, home
from book_catalog.web import get_book_service


def test_application_constructs_with_crud_routes() -> None:
    app = create_app()

    assert isinstance(app, FastAPI)
    assert str(app.url_path_for("home")) == "/"
    assert str(app.url_path_for("list_books")) == "/books"
    assert str(app.url_path_for("book_detail", book_id="7")) == "/books/7"


def test_major_get_routes_declare_server_rendered_responses() -> None:
    # Given
    routes = (*home.router.routes, *books.router.routes)
    expected_paths = {
        "/",
        "/showcase",
        "/books",
        "/books/new",
        "/books/{book_id}",
        "/books/{book_id}/edit",
        "/books/{book_id}/delete",
    }

    # When
    html_paths = {
        route.path
        for route in routes
        if isinstance(route, APIRoute)
        and route.methods == {"GET"}
        and route.response_class is HTMLResponse
    }

    # Then
    assert html_paths == expected_paths


def test_database_routes_receive_the_service_dependency() -> None:
    # Given
    routes = (*home.router.routes, *books.router.routes)
    expected_names = {
        "list_books",
        "create_book",
        "book_detail",
        "edit_book",
        "update_book",
        "confirm_delete",
        "delete_book",
    }

    # When
    injected_names = {
        route.name
        for route in routes
        if isinstance(route, APIRoute)
        and any(dependency.call is get_book_service for dependency in route.dependant.dependencies)
    }
    session_dependencies = {
        dependency.dependencies[0].call
        for route in routes
        if isinstance(route, APIRoute)
        for dependency in route.dependant.dependencies
        if dependency.call is get_book_service and len(dependency.dependencies) == 1
    }

    # Then
    assert injected_names == expected_names
    assert session_dependencies == {get_session}
