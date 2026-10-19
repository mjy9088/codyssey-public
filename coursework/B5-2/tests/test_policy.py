"""Static enforcement for handwritten graph and sorting algorithms."""

import ast
from pathlib import Path
from typing import Final

SOURCE_ROOT: Final = Path(__file__).resolve().parents[1] / "mini_git"
FORBIDDEN_MODULES: Final = frozenset({"bisect", "graphlib", "heapq", "igraph", "networkx"})
FORBIDDEN_RUNTIME_MODULES: Final = frozenset(
    {
        "dbm",
        "dulwich",
        "git",
        "http",
        "os",
        "pathlib",
        "pickle",
        "requests",
        "shelve",
        "shutil",
        "socket",
        "sqlite3",
        "ssl",
        "subprocess",
        "tempfile",
        "urllib",
    }
)
FORBIDDEN_RUNTIME_CALLS: Final = frozenset(
    {"Popen", "__import__", "compile", "eval", "exec", "open", "run", "system"}
)
ALLOWED_INTERNAL_IMPORTS: Final[dict[str, frozenset[str]]] = {
    "__init__.py": frozenset(),
    "algorithms.py": frozenset({"mini_git.errors", "mini_git.model"}),
    "cli.py": frozenset({"mini_git.errors", "mini_git.model", "mini_git.repository"}),
    "errors.py": frozenset(),
    "model.py": frozenset(),
    "repository.py": frozenset({"mini_git.algorithms", "mini_git.errors", "mini_git.model"}),
}


def test_runtime_uses_no_sorting_api_or_graph_library() -> None:
    violations: list[str] = []

    for path in SOURCE_ROOT.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            match node:
                case ast.Import(names=names):
                    violations.extend(
                        f"{path.name}:{node.lineno}: import {alias.name}"
                        for alias in names
                        if alias.name.split(".", 1)[0] in FORBIDDEN_MODULES
                    )
                case ast.ImportFrom(module=module) if module is not None:
                    if module.split(".", 1)[0] in FORBIDDEN_MODULES:
                        violations.append(f"{path.name}:{node.lineno}: from {module}")
                case ast.Call(func=ast.Name(id="sorted")):
                    violations.append(f"{path.name}:{node.lineno}: sorted()")
                case ast.Call(func=ast.Attribute(attr="sort")):
                    violations.append(f"{path.name}:{node.lineno}: .sort()")
                case _:
                    pass

    assert violations == []


def test_runtime_has_no_git_io_network_or_subprocess_capabilities() -> None:
    violations: list[str] = []

    for path in SOURCE_ROOT.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            match node:
                case ast.Import(names=names):
                    violations.extend(
                        f"{path.name}:{node.lineno}: import {alias.name}"
                        for alias in names
                        if alias.name.split(".", 1)[0] in FORBIDDEN_RUNTIME_MODULES
                    )
                case ast.ImportFrom(module=module) if module is not None:
                    if module.split(".", 1)[0] in FORBIDDEN_RUNTIME_MODULES:
                        violations.append(f"{path.name}:{node.lineno}: from {module}")
                case ast.Call(func=ast.Name(id=name)) if name in FORBIDDEN_RUNTIME_CALLS:
                    violations.append(f"{path.name}:{node.lineno}: {name}()")
                case ast.Call(func=ast.Attribute(attr=name)) if name in FORBIDDEN_RUNTIME_CALLS:
                    violations.append(f"{path.name}:{node.lineno}: .{name}()")
                case _:
                    pass

    assert violations == []


def test_runtime_module_dependencies_follow_structural_boundaries() -> None:
    actual: dict[str, frozenset[str]] = {}

    for path in SOURCE_ROOT.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        imports = frozenset(
            node.module
            for node in ast.walk(tree)
            if isinstance(node, ast.ImportFrom)
            and node.module is not None
            and node.module.startswith("mini_git.")
        )
        actual[path.name] = imports

    assert actual == ALLOWED_INTERNAL_IMPORTS
