# Run the ledger with arbitrary CLI arguments (default: show command help).
[positional-arguments]
ledger *args='--help':
    python -m budget_app "$@"

# Demonstrate transactions, search, budgets, summaries, and CSV in disposable storage.
demo:
    #!/bin/sh
    set -eu
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    ledger() { python -m budget_app --data-dir "$scratch" "$@"; }
    printf '%s\n' demo-food | ledger category add
    printf '%s\n' 2026-01-15 expense demo-food 1600 'Synthetic lunch' meal | ledger add
    ledger list
    ledger search --category demo-food --tag meal
    ledger budget set --month 2026-01 --amount 5000
    ledger summary --month 2026-01
    ledger update --id TX-000001 --amount 1700
    ledger export --out "$scratch/january.csv" --month 2026-01
    ledger delete --id TX-000001
    ledger import --from "$scratch/january.csv"
    ledger list
    ledger delete --id TX-000001
    ledger category remove --name demo-food

# Run the stdlib tests and documented CLI/storage contract.
check:
    python -m unittest discover -s tests -v
    sh verify/test-source-contract.sh .
