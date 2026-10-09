import json
import threading
import urllib.request
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from http.client import HTTPResponse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from queue import Queue
from urllib.parse import urlsplit

from ai_git_review.errors import ApiRequestError
from ai_git_review.models import ChangeContext, GenerationOptions, ReviewKind, ReviewResult
from ai_git_review.review import OpenAIBackend, RequestBody, build_prompt

_SYNTHETIC_KEY = "synthetic-test-key"
_API_URL = "https://api.openai.com/v1/responses"


@dataclass(frozen=True, slots=True)
class StubResponse:
    status: int
    body: bytes
    content_type: str = "application/json"


@dataclass(frozen=True, slots=True)
class OutgoingCall:
    upstream_url: str
    method: str
    authorization: str | None
    content_type: str | None
    body: bytes


@dataclass(frozen=True, slots=True)
class LoopbackOpener:
    base_url: str
    calls: Queue[OutgoingCall]

    @contextmanager
    def __call__(
        self, request: urllib.request.Request, *, timeout: float
    ) -> Iterator[HTTPResponse]:
        self.calls.put(
            OutgoingCall(
                upstream_url=request.full_url,
                method=request.method,
                authorization=request.get_header("Authorization"),
                content_type=request.get_header("Content-type"),
                body=request.data or b"",
            )
        )
        path = urlsplit(request.full_url).path
        mapped = urllib.request.Request(
            f"{self.base_url}{path}",
            data=request.data,
            headers=dict(request.header_items()),
            method=request.method,
        )
        with urllib.request.urlopen(mapped, timeout=timeout) as response:
            yield response


def _context() -> ChangeContext:
    return ChangeContext(status=" M app.py", diff="+print('safe')", files=("app.py",))


def _options() -> GenerationOptions:
    return GenerationOptions(model="synthetic-model", temperature=0.3, max_tokens=321)


@contextmanager
def _local_backend(response: StubResponse) -> Iterator[tuple[OpenAIBackend, Queue[OutgoingCall]]]:
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802
            content_length = int(self.headers.get("Content-Length", "0"))
            self.rfile.read(content_length)
            self.send_response(response.status)
            self.send_header("Content-Type", response.content_type)
            self.send_header("Content-Length", str(len(response.body)))
            self.end_headers()
            self.wfile.write(response.body)

        def log_message(self, format_string: str, *args: str) -> None:
            del format_string, args

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    calls: Queue[OutgoingCall] = Queue()
    opener = LoopbackOpener(base_url=f"http://127.0.0.1:{server.server_port}", calls=calls)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    thread.start()
    try:
        yield OpenAIBackend(api_key=_SYNTHETIC_KEY, _opener=opener), calls
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)


def _api_error(response: StubResponse) -> str:
    with _local_backend(response) as (backend, _calls):
        try:
            backend.generate(ReviewKind.COMMIT, _context(), _options())
        except ApiRequestError as error:
            return str(error)
    raise AssertionError("API response was unexpectedly accepted")


def test_api_success_uses_fixed_endpoint_and_expected_request_shape() -> None:
    # Given
    output = "TITLE: test: exercise adapter\nBODY:\n- Use a local protocol stub"
    response = StubResponse(
        status=200,
        body=json.dumps({"output": [{"content": [{"type": "output_text", "text": output}]}]}).encode(),
    )

    # When
    with _local_backend(response) as (backend, calls):
        result = backend.generate(ReviewKind.COMMIT, _context(), _options())
        call = calls.get(timeout=1)

    # Then
    expected_body: RequestBody = {
        "model": "synthetic-model",
        "input": build_prompt(ReviewKind.COMMIT, _context(), _options()),
        "temperature": 0.3,
        "max_output_tokens": 321,
        "store": False,
    }
    assert result == ReviewResult(
        kind=ReviewKind.COMMIT,
        title="test: exercise adapter",
        body="- Use a local protocol stub",
    )
    assert call.upstream_url == _API_URL
    assert call.method == "POST"
    assert call.authorization == f"Bearer {_SYNTHETIC_KEY}"
    assert call.content_type == "application/json"
    assert call.body == json.dumps(expected_body).encode("utf-8")


def test_api_authentication_error_is_key_safe() -> None:
    # Given
    response = StubResponse(status=401, body=b'{"error":"synthetic unauthorized"}')

    # When
    detail = _api_error(response)

    # Then
    assert "API HTTP 401" in detail
    assert _SYNTHETIC_KEY not in detail


def test_api_rate_limit_error_is_key_safe() -> None:
    # Given
    response = StubResponse(status=429, body=b'{"error":"synthetic rate limit"}')

    # When
    detail = _api_error(response)

    # Then
    assert "API HTTP 429" in detail
    assert _SYNTHETIC_KEY not in detail


def test_api_server_error_is_key_safe() -> None:
    # Given
    response = StubResponse(status=500, body=b'{"error":"synthetic server failure"}')

    # When
    detail = _api_error(response)

    # Then
    assert "API HTTP 500" in detail
    assert _SYNTHETIC_KEY not in detail


def test_api_malformed_json_is_key_safe() -> None:
    # Given
    response = StubResponse(status=200, body=b'{"output":')

    # When
    detail = _api_error(response)

    # Then
    assert "API request failed" in detail
    assert _SYNTHETIC_KEY not in detail


def test_api_missing_output_text_is_key_safe() -> None:
    # Given
    response = StubResponse(status=200, body=b'{"output":[]}')

    # When
    detail = _api_error(response)

    # Then
    assert detail == "API response contained no output_text"
    assert _SYNTHETIC_KEY not in detail
