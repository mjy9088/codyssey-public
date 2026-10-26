from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import assert_never

from ai_git_review.backends import Backend, FixtureBackend
from ai_git_review.errors import ConfigurationError
from ai_git_review.git_data import collect_changes
from ai_git_review.models import ChangeContext, GenerationOptions, ReviewKind, ReviewResult
from ai_git_review.openai import OpenAIBackend
from ai_git_review.safety import sanitize_context


class BackendKind(StrEnum):
    FIXTURE = "fixture"
    API = "api"


@dataclass(frozen=True, slots=True)
class ReviewCommand:
    kind: ReviewKind
    backend: BackendKind
    allow_network: bool
    options: GenerationOptions
    max_diff_lines: int
    include_sensitive: bool


@dataclass(frozen=True, slots=True)
class Draft:
    context: ChangeContext
    result: ReviewResult
    api_requests: int


def generate_draft(
    command: ReviewCommand,
    repository: Path,
    environment: Mapping[str, str],
) -> Draft | None:
    """Collect, sanitize, and review one repository without mutating it."""
    _validate(command)
    context = collect_changes(repository)
    if not context.status:
        return None
    if not command.include_sensitive:
        context = sanitize_context(context, max_lines=command.max_diff_lines)
    backend = _backend(command, environment)
    return Draft(
        context=context,
        result=backend.generate(command.kind, context, command.options),
        api_requests=0 if command.backend is BackendKind.FIXTURE else 1,
    )


def _validate(command: ReviewCommand) -> None:
    if not 0 <= command.options.temperature <= 2:
        raise ConfigurationError(detail="temperature must be between 0 and 2")
    if command.options.max_tokens <= 0 or command.max_diff_lines <= 0:
        raise ConfigurationError(detail="token and diff limits must be positive")


def _backend(command: ReviewCommand, environment: Mapping[str, str]) -> Backend:
    match command.backend:
        case BackendKind.FIXTURE:
            return FixtureBackend()
        case BackendKind.API:
            if not command.allow_network:
                raise ConfigurationError(detail="API backend requires --allow-network")
            api_key = environment.get("OPENAI_API_KEY", "")
            if not api_key:
                raise ConfigurationError(detail="OPENAI_API_KEY is required for API backend")
            return OpenAIBackend(api_key=api_key)
        case unreachable:
            assert_never(unreachable)
