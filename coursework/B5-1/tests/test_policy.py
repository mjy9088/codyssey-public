from __future__ import annotations

import ast
from pathlib import Path
from typing import Final, Iterator

SOURCE_ROOT: Final = Path(__file__).resolve().parents[1] / "src" / "mini_redis"
FORBIDDEN_MODULES: Final = frozenset({"collections", "heapq"})
FORBIDDEN_NAMES: Final = frozenset({"OrderedDict", "defaultdict", "deque", "dict", "set"})
FORBIDDEN_CAPABILITY_MODULES: Final = frozenset(
    {
        "asyncio",
        "concurrent",
        "dbm",
        "http",
        "multiprocessing",
        "os",
        "pathlib",
        "pickle",
        "queue",
        "shelve",
        "shutil",
        "socket",
        "sqlite3",
        "ssl",
        "subprocess",
        "tempfile",
        "threading",
        "urllib",
    }
)
FORBIDDEN_CAPABILITY_CALLS: Final = frozenset(
    {
        "Barrier",
        "Condition",
        "Event",
        "Lock",
        "Popen",
        "Process",
        "RLock",
        "Semaphore",
        "Thread",
        "__import__",
        "compile",
        "eval",
        "exec",
        "getattr",
        "open",
    }
)


def _source_nodes() -> Iterator[tuple[Path, ast.AST]]:
    for path in SOURCE_ROOT.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            yield path, node


def _imports(node: ast.AST) -> list[str]:
    if isinstance(node, ast.Import):
        return [alias.name.split(".", 1)[0] for alias in node.names]
    if isinstance(node, ast.ImportFrom) and node.module is not None:
        return [node.module.split(".", 1)[0]]
    return []


def test_cache_internals_do_not_delegate_to_prohibited_collections() -> None:
    violations: list[str] = []
    for path, node in _source_nodes():
        violations.extend(
            f"{path.name}: import {module}"
            for module in _imports(node)
            if module in FORBIDDEN_MODULES
        )
        if isinstance(node, (ast.Dict, ast.Set, ast.DictComp, ast.SetComp)):
            violations.append(f"{path.name}:{node.lineno}: built-in collection literal")
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id in FORBIDDEN_NAMES
        ):
            violations.append(f"{path.name}:{node.lineno}: {node.func.id}()")
    assert violations == []


def test_runtime_modules_enforce_capability_boundaries() -> None:
    violations: list[str] = []
    for path, node in _source_nodes():
        violations.extend(
            f"{path.name}: import {module}"
            for module in _imports(node)
            if module in FORBIDDEN_CAPABILITY_MODULES
        )
        if isinstance(node, (ast.AsyncFunctionDef, ast.Await)):
            violations.append(f"{path.name}:{node.lineno}: asynchronous runtime behavior")
        if isinstance(node, ast.Call):
            called = node.func
            call_name = ""
            if isinstance(called, ast.Name):
                call_name = called.id
            elif isinstance(called, ast.Attribute):
                call_name = called.attr
            if call_name in FORBIDDEN_CAPABILITY_CALLS:
                violations.append(f"{path.name}:{node.lineno}: {call_name}()")
    assert violations == []
