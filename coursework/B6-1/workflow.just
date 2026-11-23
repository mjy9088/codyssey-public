# Run and display all 17 SQLite queries against a disposable database.
demo:
    #!/bin/sh
    set -eu
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    sh scripts/render-results.sh "$scratch/library.db"

# Check the schema, seed, query contract and golden results.
check:
    sh scripts/check.sh
