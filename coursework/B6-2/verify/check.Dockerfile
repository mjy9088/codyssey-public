FROM ghcr.io/astral-sh/uv@sha256:9b0b40ee26d09b0ddb3b39f0aef24174f59f766af36591d541a2e14266a20886
WORKDIR /app
ENV CATALOG_DATABASE_URL=sqlite+pysqlite:////tmp/folio-check.db \
    RUFF_CACHE_DIR=/tmp/ruff-cache \
    UV_CACHE_DIR=/tmp/uv-cache \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --locked --no-install-project
COPY src/ src/
COPY tests/ tests/
RUN uv sync --locked
CMD ["sh", "-c", "uv run ruff format --check . && uv run ruff check . && uv run basedpyright && uv run pytest -p no:cacheprovider"]
