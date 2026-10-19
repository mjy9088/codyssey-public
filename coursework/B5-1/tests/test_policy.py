import ast
from pathlib import Path
from typing import Final


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
COMMAND_ALLOWLIST: Final = frozenset(
    {"SET", "GET", "DEL", "EXISTS", "DBSIZE", "KEYS", "CONFIG", "INFO", "EXPIRE", "TTL"}
)


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


def test_runtime_modules_enforce_command_and_capability_boundaries() -> None:
    violations: list[str] = []
    command_patterns: set[str] = set()

    for path in SOURCE_ROOT.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            match node:
                case ast.Import(names=names):
                    for alias in names:
                        if alias.name.split(".", 1)[0] in FORBIDDEN_CAPABILITY_MODULES:
                            violations.append(f"{path.name}:{node.lineno}: import {alias.name}")
                case ast.ImportFrom(module=module) if module is not None:
                    if module.split(".", 1)[0] in FORBIDDEN_CAPABILITY_MODULES:
                        violations.append(f"{path.name}:{node.lineno}: from {module}")
                case ast.Call(func=ast.Name(id=name)) if name in FORBIDDEN_CAPABILITY_CALLS:
                    violations.append(f"{path.name}:{node.lineno}: {name}()")
                case ast.Call(func=ast.Attribute(attr=name)) if name in FORBIDDEN_CAPABILITY_CALLS:
                    violations.append(f"{path.name}:{node.lineno}: .{name}()")
                case ast.AsyncFunctionDef() | ast.Await():
                    violations.append(f"{path.name}:{node.lineno}: asynchronous runtime behavior")
                case ast.Match(subject=ast.Name(id="command"), cases=cases):
                    for match_case in cases:
                        match match_case.pattern:
                            case ast.MatchValue(value=ast.Constant(value=str(value))):
                                command_patterns.add(value)
                            case _:
                                pass
                case _:
                    pass

    assert command_patterns == COMMAND_ALLOWLIST
    assert violations == []
