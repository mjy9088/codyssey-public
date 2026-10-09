FROM ghcr.io/astral-sh/uv@sha256:9b0b40ee26d09b0ddb3b39f0aef24174f59f766af36591d541a2e14266a20886
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy HOME=/tmp XDG_CACHE_HOME=/tmp/cache RUFF_CACHE_DIR=/tmp/ruff-cache
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --locked --no-install-project
COPY src/ src/
COPY tests/ tests/
RUN uv sync --locked
CMD ["sh", "-c", ".venv/bin/ruff format --check . && .venv/bin/ruff check . && .venv/bin/basedpyright && .venv/bin/pytest -p no:cacheprovider"]
