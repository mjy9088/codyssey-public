FROM ghcr.io/astral-sh/uv@sha256:e4644cb5bd56fdc2c5ea3ee0525d9d21eed1603bccd6a21f887a938be7e85be1 AS uv
FROM python@sha256:adafcc17694d715c905b4c7bebd96907a1fd5cf183395f0ebc4d3428bd22d92d

ENV PATH=/work/.venv/bin:$PATH PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=/work UV_COMPILE_BYTECODE=0 UV_LINK_MODE=copy
WORKDIR /work

COPY --from=uv /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --all-groups --no-install-project

COPY mini_git/ mini_git/
COPY tests/ tests/
COPY verify/guest_check.py verify/guest_check.py
COPY main.py ./

CMD ["sh", "-c", "ruff format --no-cache --check . && ruff check --no-cache . && basedpyright && python -m pytest -p no:cacheprovider"]
