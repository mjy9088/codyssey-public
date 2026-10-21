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

forbidden_objects=$(sqlite3 -batch "$database" \
  "SELECT group_concat(type || ':' || name, '|') FROM sqlite_schema WHERE type IN ('view', 'trigger');")
if test -n "$forbidden_objects"; then
  printf 'Forbidden SQLite objects found: %s\n' "$forbidden_objects" >&2
  exit 1
fi
if grep -Eiq 'CREATE[[:space:]]+(VIEW|TRIGGER)' "$root/sql/01_schema.sql" "$root/sql/02_seed.sql" "$root/sql/03_queries.sql"; then
  printf 'Forbidden CREATE VIEW or CREATE TRIGGER statement found in SQL sources\n' >&2
  exit 1
fi

tables=$(sqlite3 -batch "$database" \
  "SELECT group_concat(name, '|') FROM (SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name);")
test "$tables" = 'books|categories|members|rentals' || { printf 'Table inventory mismatch: %s\n' "$tables" >&2; exit 1; }

column_affinities=$(sqlite3 -batch "$database" "
  WITH columns(table_name, cid, name, declared_type) AS (
    SELECT 'books', cid, name, type FROM pragma_table_xinfo('books')
    UNION ALL SELECT 'categories', cid, name, type FROM pragma_table_xinfo('categories')
    UNION ALL SELECT 'members', cid, name, type FROM pragma_table_xinfo('members')
    UNION ALL SELECT 'rentals', cid, name, type FROM pragma_table_xinfo('rentals')
  )
  SELECT group_concat(item, '|') FROM (
    SELECT table_name || '.' || name || ':' ||
      CASE
        WHEN instr(upper(declared_type), 'INT') > 0 THEN 'INTEGER'
        WHEN instr(upper(declared_type), 'CHAR') > 0
          OR instr(upper(declared_type), 'CLOB') > 0
          OR instr(upper(declared_type), 'TEXT') > 0 THEN 'TEXT'
        WHEN declared_type = '' OR instr(upper(declared_type), 'BLOB') > 0 THEN 'BLOB'
        WHEN instr(upper(declared_type), 'REAL') > 0
          OR instr(upper(declared_type), 'FLOA') > 0
          OR instr(upper(declared_type), 'DOUB') > 0 THEN 'REAL'
        ELSE 'NUMERIC'
      END AS item
    FROM columns
    ORDER BY table_name, cid
  );")
expected_column_affinities='books.book_id:INTEGER|books.category_id:INTEGER|books.isbn:TEXT|books.title:TEXT|books.author:TEXT|books.published_year:INTEGER|books.copy_count:INTEGER|categories.category_id:INTEGER|categories.name:TEXT|categories.shelf_code:TEXT|members.member_id:INTEGER|members.full_name:TEXT|members.email:TEXT|members.joined_on:TEXT|members.membership_status:TEXT|rentals.rental_id:INTEGER|rentals.member_id:INTEGER|rentals.book_id:INTEGER|rentals.borrowed_on:TEXT|rentals.due_on:TEXT|rentals.returned_on:TEXT|rentals.status:TEXT'
test "$column_affinities" = "$expected_column_affinities" || {
  printf 'Column/affinity contract mismatch: %s\n' "$column_affinities" >&2; exit 1;
}

primary_keys=$(sqlite3 -batch "$database" "
  SELECT group_concat(item, '|') FROM (
    SELECT 'books.' || name AS item FROM pragma_table_info('books') WHERE pk = 1
    UNION ALL SELECT 'categories.' || name FROM pragma_table_info('categories') WHERE pk = 1
    UNION ALL SELECT 'members.' || name FROM pragma_table_info('members') WHERE pk = 1
    UNION ALL SELECT 'rentals.' || name FROM pragma_table_info('rentals') WHERE pk = 1
    ORDER BY item
  );")
test "$primary_keys" = 'books.book_id|categories.category_id|members.member_id|rentals.rental_id' || {
  printf 'Primary-key inventory mismatch: %s\n' "$primary_keys" >&2; exit 1;
}

foreign_keys=$(sqlite3 -batch "$database" "
  SELECT group_concat(item, '|') FROM (
    SELECT 'books.' || \"from\" || '->' || \"table\" || '.' || \"to\" || ':' || on_update || ':' || on_delete AS item FROM pragma_foreign_key_list('books')
    UNION ALL SELECT 'rentals.' || \"from\" || '->' || \"table\" || '.' || \"to\" || ':' || on_update || ':' || on_delete FROM pragma_foreign_key_list('rentals')
    ORDER BY item
  );")
test "$foreign_keys" = 'books.category_id->categories.category_id:CASCADE:RESTRICT|rentals.book_id->books.book_id:CASCADE:RESTRICT|rentals.member_id->members.member_id:CASCADE:RESTRICT' || {
  printf 'Foreign-key inventory mismatch: %s\n' "$foreign_keys" >&2; exit 1;
}

not_null=$(sqlite3 -batch "$database" "
  SELECT group_concat(item, '|') FROM (
    SELECT 'books.' || name AS item FROM pragma_table_info('books') WHERE \"notnull\" = 1
    UNION ALL SELECT 'categories.' || name FROM pragma_table_info('categories') WHERE \"notnull\" = 1
    UNION ALL SELECT 'members.' || name FROM pragma_table_info('members') WHERE \"notnull\" = 1
    UNION ALL SELECT 'rentals.' || name FROM pragma_table_info('rentals') WHERE \"notnull\" = 1
    ORDER BY item
  );")
test "$not_null" = 'books.author|books.category_id|books.copy_count|books.isbn|books.published_year|books.title|categories.name|categories.shelf_code|members.email|members.full_name|members.joined_on|members.membership_status|rentals.book_id|rentals.borrowed_on|rentals.due_on|rentals.member_id|rentals.status' || {
  printf 'NOT NULL inventory mismatch: %s\n' "$not_null" >&2; exit 1;
}

unique_columns=$(sqlite3 -batch "$database" "
  SELECT group_concat(item, '|') FROM (
    SELECT 'books.' || info.name AS item FROM pragma_index_list('books') AS list JOIN pragma_index_info(list.name) AS info WHERE list.\"unique\" = 1
    UNION ALL SELECT 'categories.' || info.name FROM pragma_index_list('categories') AS list JOIN pragma_index_info(list.name) AS info WHERE list.\"unique\" = 1
    UNION ALL SELECT 'members.' || info.name FROM pragma_index_list('members') AS list JOIN pragma_index_info(list.name) AS info WHERE list.\"unique\" = 1
    UNION ALL SELECT 'rentals.' || info.name FROM pragma_index_list('rentals') AS list JOIN pragma_index_info(list.name) AS info WHERE list.\"unique\" = 1
    ORDER BY item
  );")
test "$unique_columns" = 'books.isbn|categories.name|categories.shelf_code|members.email' || {
  printf 'UNIQUE inventory mismatch: %s\n' "$unique_columns" >&2; exit 1;
}

indexes=$(sqlite3 -batch "$database" "
  WITH explicit_indexes(table_name, index_name, is_unique, is_partial) AS (
    SELECT 'books', name, \"unique\", partial FROM pragma_index_list('books') WHERE origin = 'c'
    UNION ALL SELECT 'categories', name, \"unique\", partial FROM pragma_index_list('categories') WHERE origin = 'c'
    UNION ALL SELECT 'members', name, \"unique\", partial FROM pragma_index_list('members') WHERE origin = 'c'
    UNION ALL SELECT 'rentals', name, \"unique\", partial FROM pragma_index_list('rentals') WHERE origin = 'c'
  )
  SELECT group_concat(item, '|') FROM (
    SELECT table_name || '.' || index_name || ':' || is_unique || ':' || is_partial || ':' ||
      (SELECT group_concat(name, ',') FROM (
        SELECT name FROM pragma_index_info(index_name) ORDER BY seqno
      )) AS item
    FROM explicit_indexes
    ORDER BY table_name, index_name
  );")
test "$indexes" = 'rentals.idx_rentals_book_status:0:0:book_id,status|rentals.idx_rentals_member_id:0:0:member_id' || {
  printf 'Index contract mismatch: %s\n' "$indexes" >&2; exit 1;
}

grep -Fqx 'Database dialect: SQLite 3.49.2.' "$root/README.md" || {
  printf 'README must identify the pinned SQLite 3.49.2 dialect\n' >&2; exit 1;
}
grep -Fqx -- '-- SQLite-specific: julianday() performs date arithmetic.' "$root/sql/03_queries.sql" || {
  printf 'Q11 must identify julianday() as SQLite-specific\n' >&2; exit 1;
}
grep -Fqx -- '-- SQLite-specific: sqlite_master provides schema introspection.' "$root/sql/03_queries.sql" || {
  printf 'Q17 must identify sqlite_master introspection as SQLite-specific\n' >&2; exit 1;
}

expect_rejected() {
  label=$1
  statement=$2
  if sqlite3 -batch "$database" "PRAGMA foreign_keys=ON; $statement" >/dev/null 2>&1; then
    printf '%s violation was accepted\n' "$label" >&2
    exit 1
  fi
}

expect_rejected 'categories primary-key' "INSERT INTO categories VALUES (1, 'New category', 'N-01');"
expect_rejected 'members primary-key' "INSERT INTO members VALUES (1, 'New member', 'new-member@example.test', '2026-01-01', 'active');"
expect_rejected 'books primary-key' "INSERT INTO books VALUES (1, 1, '9780000000099', 'New title', 'New author', 2020, 1);"
expect_rejected 'rentals primary-key' "INSERT INTO rentals VALUES (1, 1, 1, '2026-01-01', '2026-01-02', NULL, 'borrowed');"
expect_rejected 'categories NOT NULL' "INSERT INTO categories VALUES (91, NULL, 'N-02');"
expect_rejected 'members NOT NULL' "INSERT INTO members VALUES (91, NULL, 'null-member@example.test', '2026-01-01', 'active');"
expect_rejected 'books NOT NULL' "INSERT INTO books VALUES (91, 1, '9780000000098', NULL, 'New author', 2020, 1);"
expect_rejected 'rentals NOT NULL' "INSERT INTO rentals VALUES (91, 1, 1, '2026-01-01', NULL, NULL, 'borrowed');"
expect_rejected 'books category foreign-key' "INSERT INTO books VALUES (92, 999, '9780000000097', 'New title', 'New author', 2020, 1);"
expect_rejected 'rentals member foreign-key' "INSERT INTO rentals VALUES (92, 999, 1, '2026-01-01', '2026-01-02', NULL, 'borrowed');"
expect_rejected 'rentals book foreign-key' "INSERT INTO rentals VALUES (92, 1, 999, '2026-01-01', '2026-01-02', NULL, 'borrowed');"
expect_rejected 'categories name UNIQUE' "INSERT INTO categories VALUES (93, 'Computing', 'N-03');"
expect_rejected 'categories shelf-code UNIQUE' "INSERT INTO categories VALUES (94, 'New category', 'A-01');"
expect_rejected 'members email UNIQUE' "INSERT INTO members VALUES (93, 'Duplicate', 'ada@example.test', '2026-01-01', 'active');"
expect_rejected 'books ISBN UNIQUE' "INSERT INTO books VALUES (93, 1, '9780000000001', 'New title', 'New author', 2020, 1);"
for invalid_date in 'not-a-date' '2026-02-30' '2026-1-01'; do
  expect_rejected 'member join date' "INSERT INTO members VALUES (95, 'Date probe', 'date-probe@example.test', '$invalid_date', 'active');"
  expect_rejected 'rental borrow date' "INSERT INTO rentals VALUES (95, 1, 1, '$invalid_date', '2026-02-01', NULL, 'borrowed');"
  expect_rejected 'rental due date' "INSERT INTO rentals VALUES (95, 1, 1, '2026-01-01', '$invalid_date', NULL, 'borrowed');"
  expect_rejected 'rental return date' "INSERT INTO rentals VALUES (95, 1, 1, '2026-01-01', '2026-02-01', '$invalid_date', 'returned');"
done
expect_rejected 'return before borrowing' "INSERT INTO rentals VALUES (95, 1, 1, '2026-01-02', '2026-02-01', '2026-01-01', 'returned');"
sqlite3 -batch "$database" "PRAGMA foreign_keys=ON; BEGIN;
  INSERT INTO rentals VALUES (95, 1, 1, '2026-01-02', '2026-02-01', '2026-01-02', 'returned');
  ROLLBACK;"

counts=$(sqlite3 -batch -separator '|' "$database" \
  'SELECT (SELECT COUNT(*) FROM categories), (SELECT COUNT(*) FROM members), (SELECT COUNT(*) FROM books), (SELECT COUNT(*) FROM rentals);')
test "$counts" = '10|10|12|15' || { printf 'Unexpected seed counts: %s\n' "$counts" >&2; exit 1; }

query_count=$(grep -c '^-- Q[0-9][0-9] ' "$root/sql/03_queries.sql")
if test "$query_count" -ne 17; then
  printf 'Expected exactly 17 documented queries, found %s\n' "$query_count" >&2
  exit 1
fi
for query_number in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17; do
  description=$(awk -v label="Q$query_number" '$0 ~ "^-- " label " " { sub("^-- " label " ", ""); print; exit }' "$root/sql/03_queries.sql")
  if test -z "$description"; then
    printf '%s is missing a non-empty one-line description\n' "Q$query_number" >&2
    exit 1
  fi
done

query_keyword_count() {
  label=$1
  keyword=$2
  awk -v label="$label" -v keyword="$keyword" '
    $0 ~ "^-- " label " " { active = 1; next }
    active && $0 ~ /^-- Q[0-9][0-9] / { active = 0 }
    active && index($0, keyword) { count++ }
    END { print count + 0 }
  ' "$root/sql/03_queries.sql"
}

for query_number in 01 02 03 04; do
  if test "$(awk -v label="Q$query_number" '$0 ~ "^-- " label " Basic: [^[:space:]].*" { found = 1 } END { print found + 0 }' "$root/sql/03_queries.sql")" -ne 1; then
    printf '%s must be identified as a Basic query with a description\n' "Q$query_number" >&2
    exit 1
  fi
done
for query_number in 05 06 07 08; do
  if test "$(awk -v label="Q$query_number" '$0 ~ "^-- " label " (Inner join|Left join): [^[:space:]].*" { found = 1 } END { print found + 0 }' "$root/sql/03_queries.sql")" -ne 1; then
    printf '%s must be identified as a join query with a description\n' "Q$query_number" >&2
    exit 1
  fi
done
for query_number in 09 10 11; do
  if test "$(awk -v label="Q$query_number" '$0 ~ "^-- " label " Aggregate: [^[:space:]].*" { found = 1 } END { print found + 0 }' "$root/sql/03_queries.sql")" -ne 1; then
    printf '%s must be identified as an Aggregate query with a description\n' "Q$query_number" >&2
    exit 1
  fi
  if test "$(query_keyword_count "Q$query_number" 'GROUP BY')" -lt 1; then
    printf '%s must contain GROUP BY\n' "Q$query_number" >&2
    exit 1
  fi
done
basic_where=0; basic_order=0; basic_limit=0
join_inner=0; join_left=0; aggregate_functions=0
for query_number in 01 02 03 04; do
  test "$(query_keyword_count "Q$query_number" WHERE)" -gt 0 && basic_where=1
  test "$(query_keyword_count "Q$query_number" 'ORDER BY')" -gt 0 && basic_order=1
  test "$(query_keyword_count "Q$query_number" LIMIT)" -gt 0 && basic_limit=1
done
for query_number in 05 06 07 08; do
  test "$(query_keyword_count "Q$query_number" 'INNER JOIN')" -gt 0 && join_inner=$((join_inner + 1))
  test "$(query_keyword_count "Q$query_number" 'LEFT JOIN')" -gt 0 && join_left=$((join_left + 1))
done
for function_name in COUNT SUM AVG; do
  if test "$(query_keyword_count Q09 "$function_name")" -gt 0 || test "$(query_keyword_count Q10 "$function_name")" -gt 0 || test "$(query_keyword_count Q11 "$function_name")" -gt 0; then
    aggregate_functions=$((aggregate_functions + 1))
  fi
done
test "$basic_where$basic_order$basic_limit" = 111 || { printf 'Q01-Q04 must collectively contain WHERE, ORDER BY, and LIMIT\n' >&2; exit 1; }
test "$join_inner" -ge 2 || { printf 'Q05-Q08 must contain at least two INNER JOIN queries\n' >&2; exit 1; }
test "$join_left" -ge 1 || { printf 'Q05-Q08 must contain at least one LEFT JOIN query\n' >&2; exit 1; }
test "$aggregate_functions" -ge 2 || { printf 'Q09-Q11 must collectively use at least two of COUNT, SUM, and AVG\n' >&2; exit 1; }
grep -q 'NOT EXISTS' "$root/sql/03_queries.sql" || { printf 'Missing NOT EXISTS query\n' >&2; exit 1; }
grep -q '^UPDATE rentals' "$root/sql/03_queries.sql" || { printf 'Missing UPDATE rentals query\n' >&2; exit 1; }
grep -q '^DELETE FROM rentals' "$root/sql/03_queries.sql" || { printf 'Missing DELETE FROM rentals query\n' >&2; exit 1; }
grep -q '^CREATE INDEX' "$root/sql/03_queries.sql" || { printf 'Missing CREATE INDEX query\n' >&2; exit 1; }

sqlite3 -batch -header -separator '|' "$database" < "$root/sql/03_queries.sql" > "$actual"
diff -u "$root/results/expected.txt" "$actual"

state=$(sqlite3 -batch -separator '|' "$database" \
  "SELECT status, returned_on FROM rentals WHERE rental_id=5; SELECT COUNT(*) FROM rentals; SELECT status FROM rentals WHERE rental_id=16;")
test "$state" = "returned|2026-02-12
15
borrowed" || { printf 'Mutation state mismatch\n' >&2; exit 1; }

printf 'SQL-CHECK-PASS tables=4 schema-contracts=pass seeds=%s queries=%s\n' "$counts" "$query_count"
