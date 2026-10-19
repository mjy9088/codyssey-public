from fastapi.routing import APIRoute

from book_catalog.main import create_app
from book_catalog.routers import auth, books, home, loans
from book_catalog.web import require_auth


def test_application_imports_with_all_expected_routes() -> None:
    application = create_app()

    assert application.title == "Folio lending library"


def test_route_inventory_marks_every_core_route_as_protected() -> None:
    # Given
    routes = (*auth.router.routes, *home.router.routes, *books.router.routes, *loans.router.routes)
    expected_protected = {
        ("GET", "/"),
        ("GET", "/showcase"),
        ("GET", "/books"),
        ("GET", "/books/new"),
        ("POST", "/books"),
        ("GET", "/books/{book_id}"),
        ("GET", "/books/{book_id}/edit"),
        ("POST", "/books/{book_id}"),
        ("POST", "/books/{book_id}/delete"),
        ("GET", "/loans"),
        ("POST", "/books/{book_id}/borrow"),
        ("POST", "/loans/{loan_id}/return"),
        ("POST", "/logout"),
    }

    # When
    protected = {
        (method, route.path)
        for route in routes
        if isinstance(route, APIRoute)
        and any(dependency.call is require_auth for dependency in route.dependant.dependencies)
        for method in route.methods or set()
    }
    public_login = {
        (method, route.path)
        for route in routes
        if isinstance(route, APIRoute) and route.path == "/login"
        for method in route.methods or set()
    }

    # Then
    assert protected == expected_protected
    assert public_login == {("GET", "/login"), ("POST", "/login")}
