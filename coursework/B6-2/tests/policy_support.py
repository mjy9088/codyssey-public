import ast
import re
import shlex
from collections.abc import Iterator
from pathlib import Path
from typing import Final

ROOT: Final = Path(__file__).resolve().parents[1]
PACKAGE: Final = ROOT / "src/book_catalog"
PROJECT_NAME: Final = "folio-book-catalog"
RUNTIME_DEPENDENCIES: Final = {
    "fastapi",
    "jinja2",
    "python-multipart",
    "sqlalchemy",
    "uvicorn",
}
PERSISTENCE_METHODS: Final = {
    "add",
    "commit",
    "delete",
    "execute",
    "get",
    "query",
    "refresh",
    "scalar",
    "scalars",
}
STATEMENT_BUILDERS: Final = {"delete", "insert", "select", "update"}
DEPENDENCY_NAME: Final = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?")


def python_files(layer: str) -> tuple[Path, ...]:
    return tuple(
        sorted(path for path in (PACKAGE / layer).glob("*.py") if path.name != "__init__.py")
    )


def parse_tree(path: Path) -> ast.Module:
    return ast.parse(path.read_text(), filename=str(path))


def imported_modules(tree: ast.Module) -> set[str]:
    modules: set[str] = set()
    for node in ast.walk(tree):
        match node:
            case ast.Import(names=names):
                modules.update(alias.name for alias in names)
            case ast.ImportFrom(module=module) if module is not None:
                modules.add(module)
            case _:
                continue
    return modules


def _sqlalchemy_names(tree: ast.Module) -> tuple[set[str], set[str]]:
    builders: set[str] = set()
    modules: set[str] = set()
    for node in ast.walk(tree):
        match node:
            case ast.Import(names=names):
                modules.update(
                    alias.asname or alias.name.split(".")[0]
                    for alias in names
                    if alias.name.startswith("sqlalchemy")
                )
            case ast.ImportFrom(module=module, names=names):
                if module is not None and module.startswith("sqlalchemy"):
                    builders.update(
                        alias.asname or alias.name
                        for alias in names
                        if alias.name in STATEMENT_BUILDERS
                    )
            case _:
                continue
    return builders, modules


def _is_session_receiver(node: ast.expr) -> bool:
    match node:
        case ast.Name(id=name):
            return name == "session" or name.endswith("_session")
        case ast.Attribute(attr=name):
            return name == "session" or name.endswith("_session")
        case _:
            return False


def persistence_lines(path: Path) -> tuple[int, ...]:
    tree = parse_tree(path)
    builders, modules = _sqlalchemy_names(tree)
    lines: list[int] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        match node.func:
            case ast.Name(id=name) if name in builders:
                lines.append(node.lineno)
            case ast.Attribute(value=ast.Name(id=owner), attr=name) if (
                owner in modules and name in STATEMENT_BUILDERS
            ):
                lines.append(node.lineno)
            case ast.Attribute(value=receiver, attr=name) if (
                name in PERSISTENCE_METHODS and _is_session_receiver(receiver)
            ):
                lines.append(node.lineno)
            case _:
                continue
    return tuple(lines)


def dependency_name(requirement: str) -> str:
    match = DEPENDENCY_NAME.match(requirement)
    assert match is not None
    return re.sub(r"[-_.]+", "-", match.group()).lower()


def shell_commands(markdown: str) -> Iterator[tuple[str, ...]]:
    shell_block = False
    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("```"):
            language = stripped.removeprefix("```").strip()
            shell_block = language in {"bash", "sh", "shell"} if not shell_block else False
        elif shell_block and stripped and not stripped.startswith("#"):
            yield tuple(shlex.split(stripped, comments=True))
