import ast

from tests.policy_support import (
    PACKAGE,
    imported_modules,
    parse_tree,
    persistence_lines,
    python_files,
)


def test_routers_depend_on_services_instead_of_persistence() -> None:
    # Given
    forbidden = (
        "sqlalchemy",
        "book_catalog.database",
        "book_catalog.models",
        "book_catalog.repositories",
    )

    # When
    violations = {
        path.name: sorted(
            module for module in imported_modules(parse_tree(path)) if module.startswith(forbidden)
        )
        for path in python_files("routers")
    }

    # Then
    assert all(not modules for modules in violations.values()), violations


def test_services_do_not_construct_http_responses() -> None:
    # Given
    service_trees = {path.name: parse_tree(path) for path in python_files("services")}

    # When
    framework_imports = {
        name: sorted(
            module
            for module in imported_modules(tree)
            if module.startswith(("fastapi", "starlette"))
        )
        for name, tree in service_trees.items()
    }
    response_calls = {
        name: node.lineno
        for name, tree in service_trees.items()
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, (ast.Name, ast.Attribute))
        and (node.func.id if isinstance(node.func, ast.Name) else node.func.attr).endswith(
            "Response"
        )
    }

    # Then
    assert all(not modules for modules in framework_imports.values()), framework_imports
    assert not response_calls, response_calls


def test_repositories_exclusively_own_queries_and_commits() -> None:
    # Given
    source_files = tuple(PACKAGE.rglob("*.py"))

    # When
    persistence = {
        path: persistence_lines(path) for path in source_files if persistence_lines(path)
    }
    repository_calls = {
        path: lines for path, lines in persistence.items() if path.parent.name == "repositories"
    }

    # Then
    assert persistence == repository_calls, persistence
    assert repository_calls
    assert all(
        "commit"
        in {
            node.func.attr
            for node in ast.walk(parse_tree(path))
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
        }
        for path in python_files("repositories")
    )
