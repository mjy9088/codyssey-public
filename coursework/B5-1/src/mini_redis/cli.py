import shlex
import sys
from typing import TextIO

from mini_redis.store import MiniRedis


def _arity(command: str) -> str:
    return f"(error) ERR wrong number of arguments for '{command}' command"


def _integer(raw: str) -> int | None:
    try:
        return int(raw)
    except ValueError:
        return None


def execute(store: MiniRedis, line: str) -> str:
    """Parse and execute one untrusted input line without code evaluation."""
    try:
        parts = shlex.split(line)
    except ValueError:
        return "(error) ERR invalid command syntax"
    if not parts:
        return ""
    command = parts[0].upper()
    args = parts[1:]
    match command:
        case "SET":
            if len(args) != 2:
                return _arity(command)
            result = store.set(args[0], args[1])
            return (
                "OK"
                if result == "OK"
                else "(error) OOM command not allowed when used_memory > 'maxmemory'"
            )
        case "GET":
            if len(args) != 1:
                return _arity(command)
            value = store.get(args[0])
            return "(nil)" if value is None else f'"{value}"'
        case "DEL":
            if len(args) != 1:
                return _arity(command)
            return f"(integer) {store.delete(args[0])}"
        case "EXISTS":
            if len(args) != 1:
                return _arity(command)
            return f"(integer) {store.exists(args[0])}"
        case "DBSIZE":
            if args:
                return _arity(command)
            return f"(integer) {store.dbsize()}"
        case "KEYS":
            if args:
                return _arity(command)
            keys = store.keys()
            if not keys:
                return "(empty array)"
            return "\n".join(f'{index}) "{key}"' for index, key in enumerate(keys, 1))
        case "CONFIG":
            if len(args) != 3 or args[0].upper() != "SET" or args[1].lower() != "maxmemory":
                return _arity(command)
            byte_limit = _integer(args[2])
            if byte_limit is None or byte_limit < 0:
                return "(error) ERR value is not an integer or out of range"
            return store.configure_maxmemory(byte_limit)
        case "INFO":
            if len(args) != 1 or args[0].lower() != "memory":
                return _arity(command)
            return store.info_memory()
        case "EXPIRE":
            if len(args) != 2:
                return _arity(command)
            seconds = _integer(args[1])
            if seconds is None:
                return "(error) ERR value is not an integer or out of range"
            return f"(integer) {store.expire(args[0], seconds)}"
        case "TTL":
            if len(args) != 1:
                return _arity(command)
            return f"(integer) {store.ttl(args[0])}"
        case _:
            return f"(error) ERR unknown command '{command}'"


def repl(source: TextIO = sys.stdin, output: TextIO = sys.stdout) -> None:
    """Run a prompt-driven loop until EOF, exit, or quit."""
    store = MiniRedis()
    interactive = source.isatty()
    while True:
        if interactive:
            output.write("mini-redis> ")
            output.flush()
        line = source.readline()
        if line == "":
            return
        if line.strip().lower() in ("exit", "quit"):
            return
        result = execute(store, line)
        if result:
            output.write(f"{result}\n")
            output.flush()


def main() -> None:
    repl()


if __name__ == "__main__":
    main()
