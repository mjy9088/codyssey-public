from io import StringIO

from mini_redis.cli import execute, repl
from mini_redis.store import MiniRedis


def test_execute_supports_quoted_values_and_safe_parse_errors() -> None:
    store = MiniRedis()

    assert execute(store, 'SET greeting "hello world"') == "OK"
    assert execute(store, "GET greeting") == '"hello world"'
    assert execute(store, 'SET broken "unterminated') == (
        "(error) ERR invalid command syntax"
    )
    assert execute(store, "CONFIG SET maxmemory nope") == (
        "(error) ERR value is not an integer or out of range"
    )
    assert execute(store, "GET") == (
        "(error) ERR wrong number of arguments for 'GET' command"
    )
    assert execute(store, "EVAL __import__('os')") == (
        "(error) ERR unknown command 'EVAL'"
    )


def test_repl_runs_complete_user_scenario() -> None:
    source = StringIO(
        'SET user "Alice Example"\nGET user\nEXISTS user\nDBSIZE\nKEYS\nquit\n'
    )
    output = StringIO()

    repl(source=source, output=output)

    transcript = output.getvalue()
    assert '"Alice Example"' in transcript
    assert "(integer) 1" in transcript
    assert '1) "user"' in transcript
