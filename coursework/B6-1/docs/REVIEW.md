# Review guide

## Automated evidence

Run from the B6-1 directory:

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
```

A pass proves that a fresh SQLite database accepts all schema/seed scripts, has row counts `10|10|12|15`, rejects nonexistent rental members and duplicate member email, produces the checked-in results, and ends with the expected update/delete/insert state. The QEMU path proves the database work ran after guest-kernel boot rather than only in the host container.

## Manual checklist

1. Inspect the four primary keys, three foreign keys, unique natural identifiers, non-null fields, and status/date checks in `01_schema.sql`.
2. Confirm parent records precede dependent records and every table starts with at least ten rows in `02_seed.sql`.
3. Match Q01–Q17 against their one-line purposes and category labels.
4. Compare Q05's join-oriented retrieval with Q13's correlated-subquery approach.
5. Use `EXPLAIN QUERY PLAN` interactively to explore index selection; query plans are intentionally excluded from golden evidence because SQLite versions may format them differently.
6. Confirm Docker and VM services are unprivileged, have read-only roots, and use tmpfs for generated databases.

Local Docker/QEMU checks are not deployment or collaboration evidence. No remote database or real personal data is used.
