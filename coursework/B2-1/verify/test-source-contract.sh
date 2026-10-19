#!/bin/sh
set -eu

root=${1:?candidate root is required}
readme="$root/README.md"
cli="$root/budget_app/cli.py"

require_fixed() {
  tr '\n' ' ' < "$2" | tr -s '[:space:]' ' ' | grep -Fq -- "$1" || {
    printf 'Missing source contract in %s: %s\n' "$2" "$1" >&2
    exit 1
  }
}

awk '
  /^@command_boundary[[:space:]]*$/ { decorated = 1; next }
  decorated && /^def run\(/ { found = 1 }
  decorated && /^[^[:space:]#]/ { decorated = 0 }
  END { exit found ? 0 : 1 }
' "$cli" || {
  printf 'run must be decorated with command_boundary\n' >&2
  exit 1
}

for command in add list search summary budget category update delete export import; do
  require_fixed " --data-dir ./data $command" "$readme"
done

require_fixed 'transactions.jsonl' "$readme"
require_fixed 'one UTF-8 JSON transaction per line' "$readme"
require_fixed 'categories.json' "$readme"
require_fixed 'a JSON string array' "$readme"
require_fixed 'budgets.json' "$readme"
require_fixed 'a JSON object' "$readme"
require_fixed 'CSV is UTF-8 with a header' "$readme"
require_fixed 'Export requires `--month` or at least one `--from`/`--to` boundary' "$readme"

previous=0
for column in date type category amount memo tags; do
  count=$(grep -Fc "| \`$column\` |" "$readme" || true)
  test "$count" -eq 1 || {
    printf 'CSV column must appear once in the schema table: %s\n' "$column" >&2
    exit 1
  }
  line=$(grep -Fn "| \`$column\` |" "$readme" | cut -d: -f1)
  test "$line" -gt "$previous" || {
    printf 'CSV schema column is out of order: %s\n' "$column" >&2
    exit 1
  }
  previous=$line
done

printf 'PASS: decorated command boundary and README command, storage, and CSV contracts\n'
