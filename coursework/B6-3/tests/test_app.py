from book_catalog.main import create_app


def test_application_imports_with_all_expected_routes() -> None:
    application = create_app()

    assert application.title == "Folio lending library"
