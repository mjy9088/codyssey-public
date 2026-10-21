# Folio lending library

Folio is a server-rendered FastAPI and SQLite lending application with persistent users, books,
loans, and server-side sessions. The interface follows the reusable contract in
[`DESIGN.md`](DESIGN.md) and includes catalog search and management, borrowing, returns, explicit
destructive-action confirmation, empty states, and recovery-oriented error pages.

## Runtime versions

These versions come from `pyproject.toml` and the resolved `uv.lock`.

| Runtime | Version | Source |
| --- | --- | --- |
| Python | `>=3.13` | `pyproject.toml` |
| FastAPI | `0.143.0` | `uv.lock` |
| Jinja2 | `3.1.6` | `uv.lock` |
| python-multipart | `0.0.32` | `uv.lock` |
| SQLAlchemy | `2.1.4` | `uv.lock` |
| Uvicorn | `0.54.0` | `uv.lock` |

## Environment and installation

Install Python 3.13 or newer and `uv`, then create the locked environment from this directory:

```sh
uv sync --locked
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `CATALOG_DATABASE_URL` | `sqlite+pysqlite:///data/catalog.db` | Selects the SQLite database |
| `CATALOG_CSRF_SECRET` | Local development value | Signs public and session-bound CSRF tokens |

Use a stable, private `CATALOG_CSRF_SECRET` outside local development. No external service or cloud
account is required.

## Start

```sh
uv run uvicorn book_catalog.main:app --host 0.0.0.0 --port 8000
```

Open `http://127.0.0.1:8000/login` after the server starts.

## Local data

The seed data is deterministic and intended only for local testing.

This coursework has no production database or live-schema migration workflow. When the schema
changes, discard the disposable local database and recreate it. For Compose, stop this project's
services with `docker compose down --volumes`, then start them again; this deletes its local
catalog data. For a direct local run, stop the server and remove only the selected SQLite database
before restarting. Normal restarts still preserve data unless you explicitly reset it.

| Fact | Value | Purpose |
| --- | --- | --- |
| Username | `reader` | Seeded local test account |
| Password | `correct-horse-battery-staple` | Seeded local test credential |
| Default database | `data/catalog.db` | SQLite file relative to the project working directory |
| Docker volume | `catalog-data` | Persists `/app/data` between application container runs |

## Route policy

`Public` routes can be reached without a session. Every `Protected` route uses the shared
`require_auth` dependency; state-changing forms also validate a session-bound CSRF token.

| Access | Method | Path | Purpose |
| --- | --- | --- | --- |
| Public | GET | `/login` | Render the sign-in form |
| Public | POST | `/login` | Create a server session |
| Protected | GET | `/` | Show the lending dashboard |
| Protected | GET | `/showcase` | Show the interface component showcase |
| Protected | GET | `/books` | List and search books |
| Protected | GET | `/books/new` | Render the new-book form |
| Protected | POST | `/books` | Create a book |
| Protected | GET | `/books/{book_id}` | Show book details |
| Protected | GET | `/books/{book_id}/edit` | Render the edit form |
| Protected | POST | `/books/{book_id}` | Update a book |
| Protected | POST | `/books/{book_id}/delete` | Delete an unloaned book |
| Protected | GET | `/loans` | List the signed-in member's loans |
| Protected | POST | `/books/{book_id}/borrow` | Borrow an available book |
| Protected | POST | `/loans/{loan_id}/return` | Return the member's active loan |
| Protected | POST | `/logout` | Revoke the current session |

Static assets are mounted at `/static`. The hidden `/__vm-proof` endpoint exists only for the local
VM verifier and is not part of the application route policy or OpenAPI schema.

## Major feature paths

| Feature | Path | Outcome |
| --- | --- | --- |
| Sign in | `/login` -> `/` | Establish a session and open the dashboard |
| Browse and search | `/books?q=...` -> `/books/{book_id}` | Filter inventory and inspect availability |
| Catalog management | `/books/new` -> `/books/{book_id}/edit` | Create or update catalog records |
| Borrow | `/books/{book_id}/borrow` -> `/loans?loan_status=borrowed` | Create an owned active loan |
| Return | `/loans/{loan_id}/return` -> `/loans` | Complete an owned active loan |

## Why server-side sessions

This single-application workflow needs a browser login, not an OAuth integration or a role
hierarchy. The browser receives an opaque `HttpOnly`, `SameSite=Strict` cookie while the database
stores only its digest, expiry, and owning user. Keeping session state on the server makes logout
immediately revoke that session and supports CSRF tokens bound to the current session. This is
simpler than introducing externally issued tokens while preserving explicit expiry and revocation.

## Data ownership

A user owns sessions and loans, so deleting a user cascades to both and cannot leave security or
lending rows orphaned. Books retain lending history: book deletion is rejected while any associated
loan exists. A member may borrow an available title once at a time and may return only their own
active loan.

## Verify

```sh
sh scripts/check.sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
```

`scripts/check.sh` runs formatting, static analysis, and the Python test suite. The Docker command
runs that check suite first, then drives the rendered application through pinned Chromium with
Playwright. The browser scenarios cover the authentication boundary, invalid credentials, missing
records, catalog validation and CRUD, search, borrowing conflicts, loan filters, and return
completion. The VM command runs the same browser scenarios against the application in the guest.

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
