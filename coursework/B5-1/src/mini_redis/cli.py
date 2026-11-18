"""Parse commands and present the in-memory store through a text REPL."""

from __future__ import annotations

import shlex
import sys
from dataclasses import dataclass
from typing import Callable, TextIO

from mini_redis.store import MiniRedis

_INTEGER_ERROR = "(error) ERR value is not an integer or out of range"


def _quoted(value: str, quote: str = '"') -> str:
    escaped = value.replace("\\", "\\\\").replace(quote, f"\\{quote}")
    visible = "".join(char if char.isprintable() else repr(char)[1:-1] for char in escaped)
    return f"{quote}{visible}{quote}"


def _set(store: MiniRedis, args: list[str]) -> str:
    if store.set(args[0], args[1]) == "OK":
        return "OK"
    return "(error) OOM command not allowed when used_memory > 'maxmemory'"


def _get(store: MiniRedis, args: list[str]) -> str:
    value = store.get(args[0])
    return "(nil)" if value is None else _quoted(value)


def _keys(store: MiniRedis, _args: list[str]) -> str:
    keys = store.keys()
    if not keys:
        return "(empty array)"
    return "\n".join(f"{index}) {_quoted(key)}" for index, key in enumerate(keys, 1))


def _arity(command: str) -> str:
    return f"(error) ERR wrong number of arguments for '{command}' command"


def _configure(store: MiniRedis, args: list[str]) -> str:
    if args[0].upper() != "SET" or args[1].lower() != "maxmemory":
        return _arity("CONFIG")
    try:
        return store.configure_maxmemory(int(args[2]))
    except ValueError:
        return _INTEGER_ERROR


def _info(store: MiniRedis, args: list[str]) -> str:
    if args[0].lower() != "memory":
        return _arity("INFO")
    memory = store.info_memory()
    return (
        f"used_memory:{memory.used_memory}\n"
        f"maxmemory:{memory.maxmemory}\n"
        f"evicted_keys:{memory.evicted_keys}"
    )


def _expire(store: MiniRedis, args: list[str]) -> str:
    try:
        return f"(integer) {store.expire(args[0], int(args[1]))}"
    except ValueError:
        return _INTEGER_ERROR


@dataclass(frozen=True)
class Command:
    """Bind a command name and its argument count to its handler."""

    name: str
    arity: int
    run: Callable[[MiniRedis, list[str]], str]


COMMANDS = (
    Command("SET", 2, _set),
    Command("GET", 1, _get),
    Command("DEL", 1, lambda store, args: f"(integer) {store.delete(args[0])}"),
    Command("EXISTS", 1, lambda store, args: f"(integer) {store.exists(args[0])}"),
    Command("DBSIZE", 0, lambda store, _: f"(integer) {store.dbsize()}"),
    Command("KEYS", 0, _keys),
    Command("CONFIG", 3, _configure),
    Command("INFO", 1, _info),
    Command("EXPIRE", 2, _expire),
    Command("TTL", 1, lambda store, args: f"(integer) {store.ttl(args[0])}"),
)


def execute(store: MiniRedis, line: str) -> str:
    """Parse and execute one untrusted input line without code evaluation."""
    try:
        _ = line.encode("utf-8")
        parts = shlex.split(line)
    except UnicodeEncodeError:
        return "(error) ERR input must be valid UTF-8"
    except ValueError:
        return "(error) ERR invalid command syntax"
    if not parts:
        return ""
    name, *args = parts
    name = name.upper()
    for command in COMMANDS:
        if command.name == name:
            return command.run(store, args) if len(args) == command.arity else _arity(name)
    rendered_name = _quoted(name, "'")
    return f"(error) ERR unknown command {rendered_name}"


def repl(source: TextIO = sys.stdin, output: TextIO = sys.stdout) -> None:
    """Run a prompt-driven loop until EOF, exit, or quit."""
    store = MiniRedis()
    interactive = source.isatty()
    while True:
        if interactive:
            _ = output.write("mini-redis> ")
            output.flush()
        line = source.readline()
        if line == "" or line.strip().lower() in ("exit", "quit"):
            return
        result = execute(store, line)
        if result:
            _ = output.write(f"{result}\n")
            output.flush()


def main() -> None:
    """Start the REPL on standard input and output."""
    repl()


if __name__ == "__main__":
    main()
