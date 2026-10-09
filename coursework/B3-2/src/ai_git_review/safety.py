import re

from ai_git_review.models import ChangeContext

_EMAIL = re.compile(r"(?<![\w.+-])[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}(?![\w.-])")
_SECRET = re.compile(
    r"(?i)(api[_-]?key|token|password|secret)(\s*[:=]\s*)([^\s,;]+)"
)


def sanitize_context(context: ChangeContext, max_lines: int = 200) -> ChangeContext:
    """Redact common credentials and email addresses, then enforce request bounds."""
    masked = _SECRET.sub(r"\1\2[REDACTED]", context.diff)
    masked = _EMAIL.sub("[REDACTED_EMAIL]", masked)
    bounded = "\n".join(masked.splitlines()[:max_lines])
    return ChangeContext(
        status="\n".join(context.status.splitlines()[:10]),
        diff=bounded,
        files=context.files[:10],
    )
