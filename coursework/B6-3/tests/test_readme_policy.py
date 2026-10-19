import re
import tomllib
from pathlib import Path
from typing import Final, TypedDict

from pydantic import TypeAdapter

ROOT: Final = Path(__file__).resolve().parents[1]
README: Final = (ROOT / "README.md").read_text(encoding="utf-8")
REQUIRED_COMMANDS: Final = {
    "uv sync --locked",
    "uv run uvicorn book_catalog.main:app --host 0.0.0.0 --port 8000",
    "sh scripts/check.sh",
    "sh scripts/verify.sh docker",
}
REQUIRED_ROUTES: Final = {
    ("Public", "GET", "/login"),
    ("Public", "POST", "/login"),
    ("Protected", "GET", "/"),
    ("Protected", "GET", "/showcase"),
    ("Protected", "GET", "/books"),
    ("Protected", "GET", "/books/new"),
    ("Protected", "POST", "/books"),
    ("Protected", "GET", "/books/{book_id}"),
    ("Protected", "GET", "/books/{book_id}/edit"),
    ("Protected", "POST", "/books/{book_id}"),
    ("Protected", "POST", "/books/{book_id}/delete"),
    ("Protected", "GET", "/loans"),
    ("Protected", "POST", "/books/{book_id}/borrow"),
    ("Protected", "POST", "/loans/{loan_id}/return"),
    ("Protected", "POST", "/logout"),
}


ProjectTable = TypedDict(
    "ProjectTable",
    {"requires-python": str, "dependencies": list[str]},
)


class ProjectFile(TypedDict):
    project: ProjectTable


class LockedPackage(TypedDict):
    name: str
    version: str


class LockFile(TypedDict):
    package: list[LockedPackage]


PROJECT_FILE_ADAPTER: Final = TypeAdapter(ProjectFile)
LOCK_FILE_ADAPTER: Final = TypeAdapter(LockFile)


def _section(heading: str) -> str:
    match = re.search(
        rf"^## {re.escape(heading)}\s*$\n(?P<body>.*?)(?=^## |\Z)",
        README,
        flags=re.MULTILINE | re.DOTALL,
    )
    assert match is not None, f"missing README section: {heading}"
    return match.group("body")


def _table(heading: str) -> tuple[tuple[str, ...], ...]:
    rows: list[tuple[str, ...]] = []
    for line in _section(heading).splitlines():
        if not line.startswith("|"):
            continue
        cells = tuple(cell.strip().strip("`") for cell in line.strip("|").split("|"))
        if cells and not all(set(cell) <= {"-", ":"} for cell in cells):
            rows.append(cells)
    assert len(rows) >= 2
    return tuple(rows[1:])


def test_readme_versions_match_project_and_lock_metadata() -> None:
    # Given
    project = PROJECT_FILE_ADAPTER.validate_python(
        tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    )
    lock = LOCK_FILE_ADAPTER.validate_python(
        tomllib.loads((ROOT / "uv.lock").read_text(encoding="utf-8"))
    )
    package_names = {
        dependency.partition("==")[0]: dependency.partition("==")[2]
        for dependency in project["project"]["dependencies"]
    }
    locked = {package["name"]: package["version"] for package in lock["package"]}

    # When
    documented = {name.casefold(): version for name, version, _source in _table("Runtime versions")}

    # Then
    assert documented["python"] == project["project"]["requires-python"]
    assert documented == {
        "python": project["project"]["requires-python"],
        **{name.casefold(): locked[name] for name in package_names},
    }
    assert package_names == {name: locked[name] for name in package_names}


def test_readme_documents_install_environment_start_and_verification() -> None:
    # Given / When
    operational_sections = "\n".join(
        _section(heading) for heading in ("Environment and installation", "Start", "Verify")
    )

    # Then
    assert (
        set(re.findall(r"^(?:uv|sh) .+$", operational_sections, re.MULTILINE)) >= REQUIRED_COMMANDS
    )
    environment = _table("Environment and installation")
    assert {row[0] for row in environment} == {
        "CATALOG_DATABASE_URL",
        "CATALOG_CSRF_SECRET",
    }


def test_readme_declares_test_account_and_storage() -> None:
    # Given / When
    facts = {name: value for name, value, _purpose in _table("Local data")}

    # Then
    assert facts == {
        "Username": "reader",
        "Password": "correct-horse-battery-staple",
        "Default database": "data/catalog.db",
        "Docker volume": "catalog-data",
    }


def test_readme_route_policy_lists_every_public_and_protected_route() -> None:
    # Given / When
    routes = {(access, method, path) for access, method, path, _purpose in _table("Route policy")}

    # Then
    assert routes == REQUIRED_ROUTES


def test_readme_documents_major_feature_paths() -> None:
    # Given / When
    paths: dict[str, str] = {
        feature: path for feature, path, _outcome in _table("Major feature paths")
    }

    # Then
    assert paths.keys() == {
        "Sign in",
        "Browse and search",
        "Catalog management",
        "Borrow",
        "Return",
    }
    documented_paths = "\n".join(paths.values())
    assert all(
        path in documented_paths
        for path in (
            "/login",
            "/books",
            "/books/new",
            "/books/{book_id}/borrow",
            "/loans/{loan_id}/return",
        )
    )


def test_readme_explains_server_session_choice() -> None:
    # Given / When
    rationale = _section("Why server-side sessions").casefold()

    # Then
    assert all(concept in rationale for concept in ("digest", "logout", "csrf", "oauth", "role"))
