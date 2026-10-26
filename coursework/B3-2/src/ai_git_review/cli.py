import argparse
import os
import sys
from pathlib import Path
from typing import Sequence

from ai_git_review.application import BackendKind, ReviewCommand, generate_draft
from ai_git_review.errors import ApiRequestError, ConfigurationError, GitCollectionError
from ai_git_review.errors import OutputValidationError
from ai_git_review.models import GenerationOptions, ReviewKind


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Draft commit messages and pull requests from Git changes"
    )
    parser.add_argument("kind", choices=[kind.value for kind in ReviewKind])
    parser.add_argument(
        "--backend",
        choices=[backend.value for backend in BackendKind],
        default=BackendKind.FIXTURE.value,
    )
    parser.add_argument("--allow-network", action="store_true")
    parser.add_argument("--model", default="gpt-5-mini")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--max-tokens", type=int, default=600)
    parser.add_argument("--max-diff-lines", type=int, default=200)
    parser.add_argument("--unsafe-include-sensitive", action="store_true")
    return parser


def run(arguments: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(arguments)
    command = ReviewCommand(
        kind=ReviewKind(args.kind),
        backend=BackendKind(args.backend),
        allow_network=args.allow_network,
        options=GenerationOptions(
            model=args.model,
            temperature=args.temperature,
            max_tokens=args.max_tokens,
        ),
        max_diff_lines=args.max_diff_lines,
        include_sensitive=args.unsafe_include_sensitive,
    )
    try:
        draft = generate_draft(command, Path.cwd(), os.environ)
    except (GitCollectionError, ConfigurationError, ApiRequestError, OutputValidationError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 2
    if draft is None:
        print("[INFO] No changes found; no draft generated.")
        return 0
    print(
        f"[INFO] changed_files={len(draft.context.files)} "
        f"diff_lines={len(draft.context.diff.splitlines())}"
    )
    print(f"[INFO] api_requests={draft.api_requests}")
    print("--- TITLE ---")
    print(draft.result.title)
    print("--- BODY ---")
    print(draft.result.body)
    print("--- END DRAFT: review before applying ---")
    return 0


def main() -> None:
    raise SystemExit(run())


if __name__ == "__main__":
    main()
