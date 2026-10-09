# Peer review guide

1. Run `sh scripts/verify.sh docker` and then `sh scripts/verify.sh vm`.
2. Confirm `python -m budget_app --help` describes every command and each command's
   `--help` works.
3. Add synthetic income and expense records, restart the container, and confirm
   persistence, newest-first listing, filtering, update, and delete behavior.
4. Set a budget below monthly spending and inspect the warning and category ranking.
5. Export a bounded CSV, import it into an empty data directory, and compare values.
6. Try malformed dates, zero amounts, unknown categories, missing IDs, bad JSONL,
   and a category currently in use. Errors must be concise and nonzero without a
   traceback.
7. Inspect update/delete implementation for same-directory temporary files, fsync,
   and atomic replacement. Confirm list/search consume generators rather than a
   full transaction list.

Use invented fixtures only. Local Docker and QEMU results are reproducible checks,
not evidence of public deployment or real financial activity.
