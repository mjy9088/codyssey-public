# Durable personal ledger CLI

This self-contained, standard-library-only Python application stores synthetic
personal-ledger entries safely and exposes add, list, search, summary, budget,
category, update, delete, import, and export commands. Money is represented as
positive integer minor units, never binary floating point.

## Run

Python 3.11 or newer needs no installation step:

```sh
python -m budget_app --help
python -m budget_app --data-dir ./data add
python -m budget_app --data-dir ./data list --limit 10
python -m budget_app --data-dir ./data search --from 2026-01-01 --to 2026-01-31 --category food --type expense --q lunch --tag meal
python -m budget_app --data-dir ./data summary --month 2026-01 --top 3
python -m budget_app --data-dir ./data budget set --month 2026-01 --amount 50000
python -m budget_app --data-dir ./data category add
python -m budget_app --data-dir ./data category list
python -m budget_app --data-dir ./data category remove --name other
python -m budget_app --data-dir ./data update --id TX-000001 --amount 1600 --memo corrected
python -m budget_app --data-dir ./data delete --id TX-000001
python -m budget_app --data-dir ./data export --out january.csv --month 2026-01
python -m budget_app --data-dir ./data import --from january.csv
```

`add` and `category add` are interactive. `update` is intentionally option-based;
omitted fields remain unchanged. Every parser level supports `--help`. Put the
global `--data-dir` option before the command.

With Docker, data lives in the named `ledger-data` volume:

```sh
docker compose run --rm ledger --data-dir /app/data add
docker compose run --rm ledger --data-dir /app/data list --limit 20
```

## Storage and safety

The selected data directory contains three durable files:

- `transactions.jsonl`: one UTF-8 JSON transaction per line.
- `categories.json`: a JSON string array, populated with safe defaults initially.
- `budgets.json`: a JSON object from `YYYY-MM` to positive integer minor units.

Transactions stay sorted by date and stable id. List and search read bounded blocks
from the end of JSONL, so newest-first output is chronological without materializing
the full file. Add and update share a streaming sorted rewrite; update and delete use
a same-directory temporary file, flush and fsync it, then atomically replace the
target. Category, budget, and CSV export writes use the same failure-safe pattern.

The data directory is single-writer: do not run mutating commands concurrently.
Separate readers are safe because mutations replace complete files atomically.

## CSV contract

CSV is UTF-8 with a header and exactly these columns, in order:

| Column | Required | Format |
| --- | --- | --- |
| `date` | yes | `YYYY-MM-DD` |
| `type` | yes | `income` or `expense` |
| `category` | yes | an existing category |
| `amount` | yes | positive integer minor units |
| `memo` | no | text |
| `tags` | no | comma-separated values inside the CSV field |

Invalid import rows are counted as skipped; a wrong header or unreadable file is a
command error. The header must match the documented order exactly; duplicate,
reordered, missing, or extra columns are rejected. Export requires `--month` or at
least one `--from`/`--to` boundary and refuses to overwrite an active ledger file.

## Verification

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

Docker mode runs deterministic model, persistence, CSV, corruption, and real CLI
subprocess tests. VM mode boots a real x86_64 Linux kernel under software-emulated
QEMU and runs that same suite inside the guest; its guest-generated JSON status is
the host-visible pass/fail contract. It requires Docker Engine, Compose v2, network
access for the first pinned-image/artifact build, roughly 1 GiB RAM, and no KVM or
privileged container. These local checks do not establish a public deployment.

No generated run reports are tracked: they become stale, duplicate executable
verification, grow history, and may disclose local data. See `docs/REVIEW.md` for a
manual review sequence.
