from __future__ import annotations

import csv
import os
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Final

from .errors import InputError, TransactionIdExhaustedError
from .models import ImportResult, Transaction, TransactionDraft

CSV_HEADER: Final = ("date", "type", "category", "amount", "memo", "tags")


class LedgerCsvAdapter:
    def export_file(self, output: Path, transactions: Iterable[Transaction]) -> int:
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_suffix(output.suffix + ".tmp")
        count = 0
        try:
            with temporary.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(CSV_HEADER)
                for item in transactions:
                    writer.writerow(
                        (
                            item.date.isoformat(),
                            item.type.value,
                            item.category,
                            item.amount,
                            item.memo,
                            ",".join(item.tags),
                        )
                    )
                    count += 1
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, output)
            self._sync_directory(output.parent)
        finally:
            temporary.unlink(missing_ok=True)
        return count

    def import_file(
        self,
        source: Path,
        add_transaction: Callable[[TransactionDraft], Transaction | None],
    ) -> ImportResult:
        imported = 0
        skipped = 0
        with source.open(encoding="utf-8", newline="") as handle:
            reader = csv.reader(handle)
            if tuple(next(reader, ())) != CSV_HEADER:
                raise InputError("CSV header does not match the fixed schema", "See README import/export schema")
            for row in reader:
                if len(row) != len(CSV_HEADER):
                    skipped += 1
                    continue
                date_text, type_text, category, amount, memo, tags = row
                try:
                    add_transaction(TransactionDraft(date_text, type_text, category, amount, memo, tags))
                    imported += 1
                except TransactionIdExhaustedError:
                    raise
                except InputError:
                    skipped += 1
        return ImportResult(imported, skipped)

    @staticmethod
    def _sync_directory(directory: Path) -> None:
        descriptor = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
