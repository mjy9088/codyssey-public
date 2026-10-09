#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
database=${1:-/tmp/library-results.db}
rm -f "$database"
sqlite3 -batch "$database" < "$root/sql/01_schema.sql"
sqlite3 -batch "$database" < "$root/sql/02_seed.sql"
sqlite3 -batch -header -separator '|' "$database" < "$root/sql/03_queries.sql"
