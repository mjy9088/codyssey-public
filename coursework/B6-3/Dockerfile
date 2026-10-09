FROM ghcr.io/astral-sh/uv@sha256:9b0b40ee26d09b0ddb3b39f0aef24174f59f766af36591d541a2e14266a20886
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONUNBUFFERED=1
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --locked --no-dev --no-install-project
COPY src/ src/
RUN chmod -R a+rX /app/src \
 && uv sync --locked --no-dev \
 && mkdir -p /app/data \
 && chown 65532:65532 /app/data
USER 65532:65532
EXPOSE 8000
HEALTHCHECK --interval=2s --timeout=2s --start-period=8s --retries=20 CMD ["/app/.venv/bin/python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/login', timeout=1).read()"]
CMD ["/app/.venv/bin/uvicorn", "book_catalog.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
