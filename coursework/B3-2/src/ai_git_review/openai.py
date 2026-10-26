import json
import urllib.error
import urllib.request
from collections.abc import Iterator
from contextlib import AbstractContextManager, contextmanager
from dataclasses import dataclass, field
from http.client import HTTPResponse
from typing import Protocol, TypeAlias, TypedDict, assert_never

from ai_git_review.errors import ApiRequestError
from ai_git_review.models import ChangeContext, GenerationOptions, ReviewKind, ReviewResult
from ai_git_review.policy import build_prompt, parse_result

_API_URL = "https://api.openai.com/v1/responses"
JsonValue: TypeAlias = (
    bool | int | float | str | None | list["JsonValue"] | dict[str, "JsonValue"]
)


class RequestBody(TypedDict):
    model: str
    input: str
    temperature: float
    max_output_tokens: int
    store: bool


class UrlOpener(Protocol):
    def __call__(
        self, request: urllib.request.Request, *, timeout: float
    ) -> AbstractContextManager[HTTPResponse]: ...


@contextmanager
def _open_url(request: urllib.request.Request, *, timeout: float) -> Iterator[HTTPResponse]:
    with urllib.request.urlopen(request, timeout=timeout) as response:
        yield response


@dataclass(frozen=True, slots=True)
class OpenAIBackend:
    """Send one review request through the fixed OpenAI Responses endpoint."""

    api_key: str
    _opener: UrlOpener = field(default=_open_url, repr=False, compare=False)

    def generate(
        self, kind: ReviewKind, context: ChangeContext, options: GenerationOptions
    ) -> ReviewResult:
        body: RequestBody = {
            "model": options.model,
            "input": build_prompt(kind, context, options),
            "temperature": options.temperature,
            "max_output_tokens": options.max_tokens,
            "store": False,
        }
        request = urllib.request.Request(
            _API_URL,
            data=json.dumps(body).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with self._opener(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            raise ApiRequestError(detail=f"API HTTP {error.code}: {error.reason}") from error
        except (urllib.error.URLError, TimeoutError, UnicodeError, json.JSONDecodeError) as error:
            raise ApiRequestError(detail=f"API request failed: {error}") from error
        text = _find_output_text(payload)
        if text is None:
            raise ApiRequestError(detail="API response contained no output_text")
        return parse_result(kind, text)


def _find_output_text(value: JsonValue) -> str | None:
    match value:
        case {"type": "output_text", "text": str(text)}:
            return text
        case dict():
            for nested in value.values():
                found = _find_output_text(nested)
                if found is not None:
                    return found
        case list():
            for nested in value:
                found = _find_output_text(nested)
                if found is not None:
                    return found
        case bool() | int() | float() | str() | None:
            return None
        case unreachable:
            assert_never(unreachable)
