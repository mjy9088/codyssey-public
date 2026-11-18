from io import StringIO

from mini_redis.cli import COMMANDS, execute, repl
from mini_redis.store import MiniRedis


def test_execute_supports_quoted_values_and_safe_parse_errors() -> None:
    store = MiniRedis()

    assert execute(store, 'SET greeting "hello world"') == "OK"
    assert execute(store, "GET greeting") == '"hello world"'
    assert execute(store, "SET greeting \udcff") == "(error) ERR input must be valid UTF-8"
    assert execute(store, "GET greeting") == '"hello world"'
    assert execute(store, 'SET broken "unterminated') == ("(error) ERR invalid command syntax")
    assert execute(store, "CONFIG SET maxmemory nope") == (
        "(error) ERR value is not an integer or out of range"
    )
    assert execute(store, "GET") == ("(error) ERR wrong number of arguments for 'GET' command")
    assert execute(store, "EVAL __import__('os')") == ("(error) ERR unknown command 'EVAL'")


def test_repl_runs_complete_user_scenario() -> None:
    source = StringIO(
        "\n".join(
            (
                'SET user "Alice Example"',
                f"EXPIRE user {'9' * 310}",
                "GET user",
                "EXISTS user",
                "DBSIZE",
                "KEYS",
                "quit",
                "",
            )
        )
    )
    output = StringIO()

    repl(source=source, output=output)

    transcript = output.getvalue()
    assert "(error) ERR value is not an integer or out of range\n" in transcript
    assert '"Alice Example"' in transcript
    assert "(integer) 1" in transcript
    assert '1) "user"' in transcript


def test_negative_maxmemory_is_rejected_without_changing_limit() -> None:
    store = MiniRedis()
    assert execute(store, "CONFIG SET maxmemory 12") == "OK"

    result = execute(store, "CONFIG SET maxmemory -1")

    assert result == "(error) ERR value is not an integer or out of range"
    assert "maxmemory:12" in execute(store, "INFO memory")


def test_execute_enforces_documented_command_allowlist() -> None:
    store = MiniRedis()
    accepted = (
        ("SET key value", "OK"),
        ("GET key", '"value"'),
        ("EXISTS key", "(integer) 1"),
        ("DBSIZE", "(integer) 1"),
        ("KEYS", '1) "key"'),
        ("CONFIG SET maxmemory 0", "OK"),
        ("INFO memory", "used_memory:8\nmaxmemory:0\nevicted_keys:0"),
        ("TTL key", "(integer) -1"),
        ("EXPIRE key 0", "(integer) 1"),
        ("DEL key", "(integer) 0"),
    )
    rejected = (
        "SAVE",
        "BGSAVE",
        "LOAD snapshot",
        "PUBLISH channel message",
        "SUBSCRIBE channel",
        "MULTI",
        "EXEC",
        "WATCH key",
        "EVAL payload",
        "SCRIPT LOAD payload",
        "CONFIG GET maxmemory",
        "INFO server",
    )

    assert sorted(command.name for command in COMMANDS) == sorted(
        line.split()[0] for line, _ in accepted
    )
    for command, expected in accepted:
        assert execute(store, command) == expected
    for command in rejected:
        result = execute(store, command)
        assert "unknown command" in result or "wrong number of arguments" in result


def test_execute_escapes_terminal_output() -> None:
    store = MiniRedis()
    key = "k\x1b[2J"
    value = 'line\x1b[2J"'
    assert store.set(key, value) == "OK"
    assert execute(store, f"GET '{key}'") == r'"line\x1b[2J\""'
    assert execute(store, "KEYS") == r'1) "k\x1b[2J"'
    assert execute(store, "'\x1b[2J'") == r"(error) ERR unknown command '\x1b[2J'"
    assert store.get(key) == value
