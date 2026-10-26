from typing import Protocol, assert_never

from ai_git_review.models import ChangeContext, GenerationOptions, ReviewKind, ReviewResult
from ai_git_review.policy import validate_result


class Backend(Protocol):
    def generate(
        self, kind: ReviewKind, context: ChangeContext, options: GenerationOptions
    ) -> ReviewResult: ...


class FixtureBackend:
    """Generate deterministic review drafts without credentials or network access."""

    def generate(
        self, kind: ReviewKind, context: ChangeContext, options: GenerationOptions
    ) -> ReviewResult:
        del options
        count = len(context.files)
        file_word = "file" if count == 1 else "files"
        names = ", ".join(context.files[:3]) or "tracked files"
        match kind:
            case ReviewKind.COMMIT:
                result = ReviewResult(
                    kind=kind,
                    title=f"chore: summarize changes across {count} {file_word}",
                    body=f"- Update {names}\n- Prepare changes for human review",
                )
            case ReviewKind.PR:
                result = ReviewResult(
                    kind=kind,
                    title=f"Summarize changes across {count} {file_word}",
                    body=(
                        "## Why\n- Keep the proposed change easy to review\n\n"
                        f"## What\n- Update {names}\n\n"
                        "## How to Test\n- Run the project verification command"
                    ),
                )
            case unreachable:
                assert_never(unreachable)
        validate_result(result)
        return result
