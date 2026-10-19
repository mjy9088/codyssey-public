import ast
from pathlib import Path
from typing import Final


SOURCE_ROOT: Final = Path(__file__).resolve().parents[1] / "src" / "mini_redis"
FORBIDDEN_MODULES: Final = frozenset({"collections", "heapq"})
FORBIDDEN_NAMES: Final = frozenset({"OrderedDict", "defaultdict", "deque", "dict", "set"})


def test_cache_internals_do_not_delegate_to_prohibited_collections() -> None:
    violations: list[str] = []

    for path in SOURCE_ROOT.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            match node:
                case ast.Import(names=names):
                    for alias in names:
                        if alias.name.split(".", 1)[0] in FORBIDDEN_MODULES:
                            violations.append(f"{path.name}:{node.lineno}: import {alias.name}")
                case ast.ImportFrom(module=module) if module is not None:
                    if module.split(".", 1)[0] in FORBIDDEN_MODULES:
                        violations.append(f"{path.name}:{node.lineno}: from {module}")
                case ast.Dict() | ast.Set() | ast.DictComp() | ast.SetComp():
                    violations.append(f"{path.name}:{node.lineno}: built-in collection literal")
                case ast.Call(func=ast.Name(id=name)) if name in FORBIDDEN_NAMES:
                    violations.append(f"{path.name}:{node.lineno}: {name}()")
                case _:
                    pass

    assert violations == []
