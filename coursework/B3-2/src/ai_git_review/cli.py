import argparse
import os
import sys
from pathlib import Path
from typing import Sequence

from ai_git_review.errors import ApiRequestError, ConfigurationError, GitCollectionError
from ai_git_review.errors import OutputValidationError
from ai_git_review.git_data import collect_changes
from ai_git_review.models import GenerationOptions, ReviewKind
from ai_git_review.review import Backend, FixtureBackend, OpenAIBackend
from ai_git_review.safety import sanitize_context


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Draft commit messages and pull requests from Git changes")
    parser.add_argument("kind", choices=[kind.value for kind in ReviewKind])
    parser.add_argument("--backend", choices=("fixture", "api"), default="fixture")
    parser.add_argument("--allow-network", action="store_true")
    parser.add_argument("--model", default="gpt-5-mini")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--max-tokens", type=int, default=600)
    parser.add_argument("--max-diff-lines", type=int, default=200)
    parser.add_argument("--unsafe-include-sensitive", action="store_true")
    return parser


def _backend(name: str, allow_network: bool) -> Backend:
    if name == "fixture":
        return FixtureBackend()
    if not allow_network:
        raise ConfigurationError(detail="API backend requires --allow-network")
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise ConfigurationError(detail="OPENAI_API_KEY is required for API backend")
    return OpenAIBackend(api_key=api_key)


def run(arguments: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(arguments)
    if not 0 <= args.temperature <= 2:
        print("[ERROR] temperature must be between 0 and 2", file=sys.stderr)
        return 2
    if args.max_tokens <= 0 or args.max_diff_lines <= 0:
        print("[ERROR] token and diff limits must be positive", file=sys.stderr)
        return 2
    try:
        context = collect_changes(Path.cwd())
        if not context.status:
            print("[INFO] No changes found; no draft generated.")
            return 0
        if not args.unsafe_include_sensitive:
            context = sanitize_context(context, max_lines=args.max_diff_lines)
        options = GenerationOptions(
            model=args.model,
            temperature=args.temperature,
            max_tokens=args.max_tokens,
        )
        kind = ReviewKind(args.kind)
        result = _backend(args.backend, args.allow_network).generate(kind, context, options)
    except (GitCollectionError, ConfigurationError, ApiRequestError, OutputValidationError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 2
    print(f"[INFO] changed_files={len(context.files)} diff_lines={len(context.diff.splitlines())}")
    print("[INFO] api_requests=0" if args.backend == "fixture" else "[INFO] api_requests=1")
    print("--- TITLE ---")
    print(result.title)
    print("--- BODY ---")
    print(result.body)
    print("--- END DRAFT: review before applying ---")
    return 0


def main() -> None:
    raise SystemExit(run())


if __name__ == "__main__":
    main()
