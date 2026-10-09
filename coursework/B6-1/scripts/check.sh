#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
work=${TMPDIR:-/tmp}/b6-1-check-$$
database=$work/library.db
actual=$work/results.txt
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT INT TERM

sqlite3 -batch "$database" < "$root/sql/01_schema.sql"
sqlite3 -batch "$database" < "$root/sql/02_seed.sql"

counts=$(sqlite3 -batch -separator '|' "$database" \
  'SELECT (SELECT COUNT(*) FROM categories), (SELECT COUNT(*) FROM members), (SELECT COUNT(*) FROM books), (SELECT COUNT(*) FROM rentals);')
test "$counts" = '10|10|12|15' || { printf 'Unexpected seed counts: %s\n' "$counts" >&2; exit 1; }

if sqlite3 -batch "$database" \
  "PRAGMA foreign_keys=ON; INSERT INTO rentals VALUES (99, 999, 1, '2026-01-01', '2026-01-02', NULL, 'borrowed');" \
  >/dev/null 2>&1; then
  printf 'Foreign-key violation was accepted\n' >&2
  exit 1
fi

if sqlite3 -batch "$database" \
  "INSERT INTO members VALUES (99, 'Duplicate', 'ada@example.test', '2026-01-01', 'active');" \
  >/dev/null 2>&1; then
  printf 'Unique-email violation was accepted\n' >&2
  exit 1
fi

query_count=$(grep -c '^-- Q[0-9][0-9] ' "$root/sql/03_queries.sql")
test "$query_count" -ge 15 || { printf 'Expected at least 15 documented queries\n' >&2; exit 1; }
test "$(grep -c 'INNER JOIN' "$root/sql/03_queries.sql")" -ge 2
test "$(grep -c 'LEFT JOIN' "$root/sql/03_queries.sql")" -ge 1
test "$(grep -c 'GROUP BY' "$root/sql/03_queries.sql")" -ge 3
grep -q 'NOT EXISTS' "$root/sql/03_queries.sql"
grep -q '^UPDATE rentals' "$root/sql/03_queries.sql"
grep -q '^DELETE FROM rentals' "$root/sql/03_queries.sql"
grep -q '^CREATE INDEX' "$root/sql/03_queries.sql"

sqlite3 -batch -header -separator '|' "$database" < "$root/sql/03_queries.sql" > "$actual"
diff -u "$root/results/expected.txt" "$actual"

state=$(sqlite3 -batch -separator '|' "$database" \
  "SELECT status, returned_on FROM rentals WHERE rental_id=5; SELECT COUNT(*) FROM rentals; SELECT status FROM rentals WHERE rental_id=16;")
test "$state" = "returned|2026-02-12
15
borrowed" || { printf 'Mutation state mismatch\n' >&2; exit 1; }

printf 'SQL-CHECK-PASS tables=4 seeds=%s queries=%s\n' "$counts" "$query_count"
