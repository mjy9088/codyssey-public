import ast
import io
import tokenize
import tomllib
from collections.abc import Iterator
from pathlib import Path
from typing import Final, TypedDict

from pydantic import TypeAdapter

ROOT: Final = Path(__file__).resolve().parents[1]
PACKAGE: Final = ROOT / "src/book_catalog"
RUNTIME_DEPENDENCIES: Final = {
    "fastapi": "0.143.0",
    "jinja2": "3.1.6",
    "python-multipart": "0.0.32",
    "sqlalchemy": "2.1.4",
    "uvicorn": "0.54.0",
}
AUTH_BOUNDARIES: Final = {
    "auth/__init__.py",
    "database.py",
    "routers/auth.py",
    "services/auth.py",
    "web.py",
}


class ProjectTable(TypedDict):
    dependencies: list[str]


class ProjectFile(TypedDict):
    project: ProjectTable


class LockedPackage(TypedDict):
    name: str
    version: str


class LockFile(TypedDict):
    package: list[LockedPackage]


PROJECT_FILE_ADAPTER: Final = TypeAdapter(ProjectFile)
LOCK_FILE_ADAPTER: Final = TypeAdapter(LockFile)


def _python_files(directory: str) -> tuple[Path, ...]:
    return tuple(sorted((PACKAGE / directory).glob("*.py")))


def _tree(path: Path) -> ast.Module:
    return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


def _imports(tree: ast.Module) -> Iterator[tuple[str, str | None]]:
    for node in ast.walk(tree):
        match node:
            case ast.Import(names=names):
                yield from ((alias.name, None) for alias in names)
            case ast.ImportFrom(module=module, names=names) if module is not None:
                yield from ((module, alias.name) for alias in names)
            case _:
                continue


def _nearby_comment(path: Path, line: int) -> bool:
    comments = {
        token.start[0]: token.string.removeprefix("#").strip()
        for token in tokenize.generate_tokens(
            io.StringIO(path.read_text(encoding="utf-8")).readline
        )
        if token.type == tokenize.COMMENT
    }
    return any(len(comments.get(candidate, "").split()) >= 5 for candidate in range(line - 2, line))


def test_routers_depend_on_services_instead_of_sqlalchemy_data_access() -> None:
    # Given / When
    imported_modules = {
        module for path in _python_files("routers") for module, _ in _imports(_tree(path))
    }

    # Then
    assert not any(
        module == "sqlalchemy" or module.startswith("sqlalchemy.") for module in imported_modules
    )
    assert not any(module.startswith("book_catalog.repositories") for module in imported_modules)
    assert not any(module.startswith("book_catalog.models") for module in imported_modules)
    assert "book_catalog.database" not in imported_modules


def test_services_do_not_render_http_responses_or_templates() -> None:
    # Given / When
    imports = {
        (module, name)
        for path in _python_files("services")
        for module, name in _imports(_tree(path))
    }

    # Then
    assert not any(
        module == "fastapi" or module.startswith(("fastapi.", "starlette."))
        for module, _ in imports
    )
    assert not any(name == "templates" for _, name in imports)


def test_sqlalchemy_runtime_access_stays_in_persistence_boundaries() -> None:
    # Given
    allowed_roots = {"database.py", "models", "repositories", "web.py"}

    # When
    sqlalchemy_importers = {
        path.relative_to(PACKAGE).as_posix()
        for path in PACKAGE.rglob("*.py")
        if any(
            module == "sqlalchemy" or module.startswith("sqlalchemy.")
            for module, _ in _imports(_tree(path))
        )
    }

    # Then
    assert sqlalchemy_importers
    assert all(path.split("/", maxsplit=1)[0] in allowed_roots for path in sqlalchemy_importers)
    for path in (path for path in _python_files("repositories") if path.name != "__init__.py"):
        imports = {module for module, _ in _imports(_tree(path))}
        assert any(module == "sqlalchemy" or module.startswith("sqlalchemy.") for module in imports)

    data_operations = {
        "add",
        "add_all",
        "commit",
        "execute",
        "flush",
        "query",
        "refresh",
        "scalar",
        "scalars",
    }
    operation_locations = {
        path.relative_to(PACKAGE).as_posix()
        for path in PACKAGE.rglob("*.py")
        if any(
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr in data_operations
            for node in ast.walk(_tree(path))
        )
    }
    assert all(
        path == "database.py" or path.startswith("repositories/") for path in operation_locations
    )


def test_auth_implementation_imports_stay_in_auth_service_and_web_boundaries() -> None:
    # Given / When
    auth_importers = {
        path.relative_to(PACKAGE).as_posix()
        for path in PACKAGE.rglob("*.py")
        if any(module.startswith("book_catalog.auth") for module, _ in _imports(_tree(path)))
    }

    # Then
    assert auth_importers == AUTH_BOUNDARIES


def test_no_oauth_or_role_hierarchy_is_present() -> None:
    # Given / When
    forbidden_identifiers: set[tuple[str, str]] = set()
    oauth_imports: set[tuple[str, str]] = set()
    for path in PACKAGE.rglob("*.py"):
        relative = path.relative_to(PACKAGE).as_posix()
        tree = _tree(path)
        forbidden_identifiers.update(
            (relative, identifier)
            for node in ast.walk(tree)
            for identifier in (
                node.id
                if isinstance(node, ast.Name)
                else node.name
                if isinstance(node, ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef)
                else node.attr
                if isinstance(node, ast.Attribute)
                else "",
            )
            if identifier.casefold() in {"role", "roles"}
        )
        oauth_imports.update(
            (relative, module)
            for module, name in _imports(tree)
            if "oauth" in module.casefold() or (name is not None and "oauth" in name.casefold())
        )

    # Then
    assert not forbidden_identifiers
    assert not oauth_imports


def test_runtime_dependencies_are_the_locked_fastapi_stack_only() -> None:
    # Given
    project = PROJECT_FILE_ADAPTER.validate_python(
        tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    )
    lock = LOCK_FILE_ADAPTER.validate_python(
        tomllib.loads((ROOT / "uv.lock").read_text(encoding="utf-8"))
    )
    expected = {f"{name}=={version}" for name, version in RUNTIME_DEPENDENCIES.items()}

    # When
    declared = set(project["project"]["dependencies"])
    locked = {
        package["name"]: package["version"]
        for package in lock["package"]
        if package["name"] in RUNTIME_DEPENDENCIES
    }

    # Then
    assert declared == expected
    assert locked == RUNTIME_DEPENDENCIES


def test_deletion_policies_keep_nearby_rationale_comments() -> None:
    # Given
    policies = {
        PACKAGE / "models/book.py": ("loans", ast.AnnAssign),
        PACKAGE / "models/user.py": ("loans", ast.AnnAssign),
        PACKAGE / "services/books.py": ("delete", ast.FunctionDef),
    }

    # When
    policy_lines: dict[Path, int] = {}
    for path, (name, node_type) in policies.items():
        for node in ast.walk(_tree(path)):
            if isinstance(node, ast.AnnAssign) and node_type is ast.AnnAssign:
                if isinstance(node.target, ast.Name) and node.target.id == name:
                    policy_lines[path] = node.lineno
            elif (
                isinstance(node, ast.FunctionDef)
                and node_type is ast.FunctionDef
                and node.name == name
            ):
                policy_lines[path] = node.lineno

    # Then
    assert policy_lines.keys() == policies.keys()
    assert all(_nearby_comment(path, line) for path, line in policy_lines.items())
