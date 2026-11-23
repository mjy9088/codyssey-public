# Browse, sign in, manage books, borrow and return at http://127.0.0.1:8000.
demo:
    uv run --locked uvicorn book_catalog.main:app --host "${COURSEWORK_LISTEN:-127.0.0.1}" --port 8000

# Exercise local UI flows against a fresh SQLite database.
browser:
    #!/bin/sh
    set -eu
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    export CATALOG_DATABASE_URL="sqlite+pysqlite:///$scratch/catalog.db"
    unset BASE_URL
    COURSEWORK_NATIVE_BROWSER=1 pnpm run test:browser

# Check types, unit tests, and browser features on the host.
check: _python-check
    pnpm run check
    just browser
