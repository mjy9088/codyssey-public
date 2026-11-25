# Run the catalog UI for search, create, edit and delete at http://127.0.0.1:8000.
demo:
    uv run --locked uvicorn book_catalog.main:app --host "${COURSEWORK_LISTEN:-127.0.0.1}" --port 8000

# Exercise local CRUD against a fresh SQLite database.
browser:
    #!/bin/sh
    set -eu
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    export CATALOG_DATABASE_URL="sqlite+pysqlite:///$scratch/catalog.db"
    unset BASE_URL
    COURSEWORK_NATIVE_BROWSER=1 npm run test:e2e

# Check style, types, unit tests and browser CRUD on the host.
check: _python-check browser
