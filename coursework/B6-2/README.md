# Folio: server-rendered book catalog

Folio is a small FastAPI application for cataloging books by title, author, and publication year. Every major screen is rendered on the server with Jinja, and every create, read, update, delete, and search operation reaches SQLite through a synchronous SQLAlchemy `Session` supplied by FastAPI `Depends`.

## Run locally with uv

Python 3.13 and [uv](https://docs.astral.sh/uv/) are required.

```sh
uv sync --locked
uv run uvicorn book_catalog.main:app --host 0.0.0.0 --port 8000
# Open http://localhost:8000
```

The default database is `data/catalog.db`. Override it with `CATALOG_DATABASE_URL`, for example `sqlite+pysqlite:////tmp/folio.db`. Set `CATALOG_CSRF_SECRET` to a stable random value outside local development.

## Verify

```sh
# Strict lint, format, types, and unit/integration tests in a pinned container
sh scripts/check.sh

# Real app + SQLite + Chromium CRUD flow
sh scripts/verify.sh docker

# The same real app running inside an x86_64 QEMU TCG guest
sh scripts/verify.sh vm

# Both runtime paths
sh scripts/verify.sh all
```

The workflows need Docker Engine, Compose v2, and a POSIX shell. They do not need host Python, Node, QEMU, KVM, privileged mode, added capabilities, a bind mount, a Docker socket inside a workload, or credentials.

## Request flow

```text
browser form
  -> router (HTTP, Form parsing, CSRF, TemplateResponse / 303 redirect)
  -> service (normalization and use-case decisions)
  -> repository (SQLAlchemy statements)
  -> synchronous Session (Depends)
  -> SQLite file
```

The model is deliberately narrow so it can be extended later: `Book(id, title, author, year)`. Routes cover home, list/search, detail, create, edit, delete confirmation, missing records, invalid input, and a design-system showcase. Successful mutations use `RedirectResponse(status_code=303)`, so browser refresh repeats the final GET rather than the mutation.

CSRF protection uses a server-signed, short-lived token in every mutation form. It needs no additional runtime dependency. The development fallback secret is process-local; deployment must provide `CATALOG_CSRF_SECRET` so forms remain valid across workers and restarts.

## Boundaries

Docker and QEMU checks are local verification, not external deployment evidence. The QEMU path boots a separate Linux kernel and runs Uvicorn, FastAPI, Jinja, SQLAlchemy, and SQLite inside the guest; the browser verifier remains a Compose service. Runtime databases, screenshots, traces, reports, and logs are ignored because they become stale, duplicate automation, grow history, and may expose environment details.
