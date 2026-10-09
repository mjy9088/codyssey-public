"""Mini Git executable entry point."""

from datetime import UTC, datetime

from mini_git.cli import execute
from mini_git.repository import Repository


def main() -> int:
    """Run the interactive command loop."""
    repository = Repository(lambda: datetime.now(tz=UTC))
    while True:
        try:
            line = input("mini-git> ")
        except EOFError:
            return 0
        output, should_continue = execute(repository, line)
        if output:
            print(output)
        if not should_continue:
            return 0


if __name__ == "__main__":
    raise SystemExit(main())
