#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import signal
import shutil
import sys
from pathlib import Path
from typing import Final, TypeAlias

PlistScalar: TypeAlias = str | bytes | int | float | bool
PlistValue: TypeAlias = PlistScalar | list["PlistValue"] | dict[str, "PlistValue"]
STATE: Final = Path(os.environ["FAKE_DEFAULTS_STATE"])
LOG: Final = STATE / "calls.log"


def domain_path(domain: str) -> Path:
    return STATE / f"{domain.encode().hex()}.plist"


def load(path: Path) -> dict[str, PlistValue]:
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    if not isinstance(value, dict):
        raise SystemExit(2)
    return value


def save(path: Path, value: dict[str, PlistValue]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(value, stream, sort_keys=True)


def fails(kind: str, subject: str) -> bool:
    return subject in os.environ.get(f"FAKE_{kind}", "").split(",")


def defaults(arguments: list[str]) -> int:
    command, *rest = arguments
    if command == "domains":
        names = [bytes.fromhex(path.stem).decode() for path in STATE.glob("*.plist")]
        print(", ".join(sorted(names)))
        return 0
    domain = rest[0]
    path = domain_path(domain)
    if command == "export":
        if fails("EXPORT", domain) or not path.exists():
            return 1
        shutil.copyfile(path, Path(rest[1]))
        return 0
    if command == "import":
        counter = STATE / f".imports-{domain.encode().hex()}"
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        if os.environ.get("FAKE_INTERRUPT_AT") == f"{domain}:{count}":
            os.kill(os.getppid(), signal.SIGINT)
        if fails("IMPORT", domain) or os.environ.get("FAKE_IMPORT_AT") == f"{domain}:{count}":
            return 1
        shutil.copyfile(Path(rest[1]), path)
        return 0
    if command == "read":
        if fails("READ", domain) or not path.exists():
            return 1
        value: PlistValue = load(path)
        if len(rest) == 2:
            key = rest[1]
            if key not in value:
                return 1
            value = value[key]
        sys.stdout.buffer.write(plistlib.dumps(value))
        return 0
    if command == "delete":
        if not path.exists():
            return 1
        if len(rest) == 1:
            path.unlink()
            return 0
        data = load(path)
        if rest[1] not in data:
            return 1
        del data[rest[1]]
        save(path, data)
        return 0
    if command != "write":
        return 2
    key = rest[1]
    if fails("WRITE", f"{domain}:{key}"):
        return 1
    data = load(path) if path.exists() else {}
    option = rest[2]
    if option == "-bool":
        data[key] = rest[3].lower() == "true"
    elif option == "-array":
        entries: list[PlistValue] = []
        for literal in rest[3:]:
            marker = '_CFURLString="'
            start = literal.index(marker) + len(marker)
            url = literal[start : literal.index('"', start)]
            entries.append({"tile-data": {"file-data": {"_CFURLString": url, "_CFURLStringType": 15}}, "tile-type": "file-tile"})
        data[key] = entries
    elif option == "-array-add":
        current = data.setdefault(key, [])
        if not isinstance(current, list):
            return 2
        literal = rest[3]
        if "InputSourceKind" in literal:
            current.append({"InputSourceKind": "Keyboard Layout", "KeyboardLayout Name": "Korean 2-Set"})
        else:
            marker = '_CFURLString="'
            start = literal.index(marker) + len(marker)
            current.append({"tile-data": {"file-data": {"_CFURLString": literal[start : literal.index('"', start)]}}})
    else:
        return 2
    save(path, data)
    return 0


def locate(root: PlistValue, path: str) -> tuple[PlistValue, str]:
    parts = [part.strip("'") for part in path.removeprefix(":").split(":")]
    current = root
    for part in parts[:-1]:
        current = current[int(part)] if isinstance(current, list) else current[part]
    return current, parts[-1]


def plistbuddy(arguments: list[str]) -> int:
    command = arguments[arguments.index("-c") + 1]
    path = Path(arguments[-1])
    data = load(path)
    operation, remainder = command.split(" ", 1)
    tail: list[str] = []
    target = remainder
    if operation == "Add":
        for kind in (" dict", " array", " bool ", " integer ", " string "):
            marker = remainder.rfind(kind)
            if marker >= 0:
                target = remainder[:marker]
                tail = remainder[marker + 1 :].split(" ")
                break
    if ":Bundle ID" in target or ":Input Mode" in target:
        return 2
    try:
        parent, name = locate(data, target)
        if operation == "Print":
            value = parent[int(name)] if isinstance(parent, list) else parent[name]
            print(value)
            return 0
        if operation == "Delete":
            if isinstance(parent, list):
                del parent[int(name)]
            else:
                del parent[name]
        elif operation == "Add":
            kind = tail[0]
            value: PlistValue
            if kind == "dict":
                value = {}
            elif kind == "array":
                value = []
            elif kind == "bool":
                value = tail[1].lower() == "true"
            elif kind == "integer":
                value = int(tail[1])
            else:
                value = " ".join(tail[1:]).strip("'")
            if isinstance(parent, list):
                index = int(name)
                parent.append(value) if index == len(parent) else parent.insert(index, value)
            else:
                if name in parent:
                    return 1
                parent[name] = value
        else:
            return 2
    except (KeyError, IndexError, ValueError):
        return 1
    save(path, data)
    return 0


def main() -> int:
    STATE.mkdir(parents=True, exist_ok=True)
    name = Path(sys.argv[0]).name
    with LOG.open("a", encoding="utf-8") as stream:
        stream.write(f"{name}\t{' '.join(sys.argv[1:])}\n")
    if name == "defaults":
        return defaults(sys.argv[1:])
    if name == "PlistBuddy":
        return plistbuddy(sys.argv[1:])
    if name == "plutil" and sys.argv[1:3] == ["-create", "xml1"]:
        save(Path(sys.argv[3]), {})
        return 0
    if name == "uname":
        print("Darwin")
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
