# Folio lending library

Folio is a FastAPI and SQLite lending application with persistent users, books, loans, and
server-side sessions. Authentication and authorization are injected with FastAPI `Depends`; every
state-changing form carries a session-bound CSRF token. The seeded local account is `reader` with
password `correct-horse-battery-staple`.

The responsive server-rendered interface follows the reusable contract in [`DESIGN.md`](DESIGN.md).
It includes signed-out and authenticated shells, searchable inventory cards, catalog forms, explicit
destructive-action confirmation, loan filters, empty states, and recovery-oriented error pages.

## Run

```sh
uv sync --locked
uv run uvicorn book_catalog.main:app --host 0.0.0.0 --port 8000
```

Set `CATALOG_DATABASE_URL` to select another SQLite database and set a stable, private
`CATALOG_CSRF_SECRET` outside local development.

## Verify

```sh
sh scripts/check.sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
```

`scripts/check.sh` runs formatting, static analysis, and the Python test suite. Both verification
paths drive the rendered application through pinned Chromium with Playwright. The scenarios cover
the authentication boundary, invalid credentials, missing records, catalog validation and CRUD,
search, borrowing conflicts, loan filters, and return completion.

For an already running development server, run the browser suite directly:

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm exec playwright install chromium
corepack pnpm run check
corepack pnpm run test:browser
```

Set `BASE_URL` when the server is not at `http://127.0.0.1:8000`. The Docker path runs the real
application with a persistent volume. The VM path boots a separate x86_64 Linux kernel under QEMU
TCG and runs the same Uvicorn application inside the guest. These are local simulations, not
evidence of cloud deployment or external collaboration. Runtime databases, browser traces,
screenshots, videos, logs, and reports remain untracked because generated evidence becomes stale,
duplicates the automation, and can expose environment details.

## Data ownership

A user owns sessions and loans, so deleting a user cascades to both. Books retain lending history:
book deletion is rejected while any associated loan exists. A member may borrow an available title
once at a time and may return only their own active loan.
