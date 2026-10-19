"""Static enforcement for handwritten graph and sorting algorithms."""

import ast
from pathlib import Path
from typing import Final

SOURCE_ROOT: Final = Path(__file__).resolve().parents[1] / "mini_git"
FORBIDDEN_MODULES: Final = frozenset({"bisect", "graphlib", "heapq", "igraph", "networkx"})


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
