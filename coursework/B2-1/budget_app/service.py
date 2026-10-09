from __future__ import annotations

import csv
import os
from collections import defaultdict
from collections.abc import Iterator
from pathlib import Path

from .errors import InputError
from .models import (
    ImportResult,
    ExportSelection,
    Money,
    SearchCriteria,
    Summary,
    Transaction,
    TransactionChanges,
    TransactionDraft,
    TransactionId,
    TransactionType,
    parse_amount,
    parse_category,
    parse_date,
    parse_month,
    parse_type,
)
from .storage import LedgerStore


class LedgerService:
    def __init__(self, store: LedgerStore) -> None:
        self.store = store
        self.store.initialize()

    def add(
        self,
        draft: TransactionDraft,
    ) -> Transaction:
        self._require_category(draft.category)
        largest = max((int(item.id.removeprefix("TX-")) for item in self.store.iter_transactions()), default=0)
        transaction = Transaction.create(
            TransactionId(f"TX-{largest + 1:06d}"),
            draft,
        )
        self.store.upsert(transaction, require_existing=False)
        return transaction

    def search(self, criteria: SearchCriteria, limit: int | None) -> Iterator[Transaction]:
        count = 0
        for transaction in self.store.iter_transactions(latest_first=True):
            if criteria.matches(transaction):
                yield transaction
                count += 1
                if limit is not None and count >= limit:
                    return

    def update(
        self,
        transaction_id: TransactionId,
        changes: TransactionChanges,
    ) -> bool:
        if changes.category is not None:
            self._require_category(changes.category)
        for transaction in self.store.iter_transactions():
            if transaction.id == transaction_id:
                return self.store.upsert(transaction.changed(changes), require_existing=True)
        return False

    def delete(self, transaction_id: TransactionId) -> bool:
        found = False

        def retained() -> Iterator[Transaction]:
            nonlocal found
            for transaction in self.store.iter_transactions():
                if transaction.id == transaction_id:
                    found = True
                else:
                    yield transaction

        self.store.replace_transactions(retained())
        return found

    def summary(self, month: str, top: int) -> Summary:
        parse_month(month)
        income = 0
        expense = 0
        categories: dict[str, int] = defaultdict(int)
        for transaction in self.store.iter_transactions():
            if transaction.date.strftime("%Y-%m") != month:
                continue
            match transaction.type:
                case TransactionType.INCOME:
                    income += transaction.amount
                case TransactionType.EXPENSE:
                    expense += transaction.amount
                    categories[transaction.category] += transaction.amount
        ranked = tuple(sorted(categories.items(), key=lambda item: (-item[1], item[0]))[:top])
        budget = self.store.list_budgets().get(month)
        return Summary(income, expense, income - expense, ranked, budget, budget is not None and expense > budget)

    def set_budget(self, month: str, amount: str) -> None:
        parse_month(month)
        budgets = self.store.list_budgets()
        budgets[month] = parse_amount(amount)
        self.store.save_budgets(budgets)

    def add_category(self, category: str) -> bool:
        value = parse_category(category)
        categories = set(self.store.list_categories())
        if value in categories:
            return False
        categories.add(value)
        self.store.save_categories(categories)
        return True

    def remove_category(self, category: str) -> bool:
        value = parse_category(category)
        categories = set(self.store.list_categories())
        if value not in categories:
            return False
        if any(item.category == value for item in self.store.iter_transactions()):
            raise InputError("category is in use", "Update or delete its transactions first")
        categories.remove(value)
        self.store.save_categories(categories)
        return True

    def export_csv(self, output: Path, selection: ExportSelection) -> int:
        if selection.month is None and selection.date_from is None and selection.date_to is None:
            raise InputError("export requires --month or a date boundary", "Add --month YYYY-MM or --from/--to")
        criteria = self._criteria(selection)
        if self.store.is_active_path(output):
            raise InputError("export target is an active ledger file", "Choose a path outside the three data files")
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_suffix(output.suffix + ".tmp")
        count = 0
        try:
            with temporary.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(("date", "type", "category", "amount", "memo", "tags"))
                for item in self.search(criteria, limit=None):
                    writer.writerow((item.date.isoformat(), item.type.value, item.category, item.amount, item.memo, ",".join(item.tags)))
                    count += 1
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, output)
            descriptor = os.open(output.parent, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        finally:
            temporary.unlink(missing_ok=True)
        return count

    def import_csv(self, source: Path) -> ImportResult:
        imported = 0
        skipped = 0
        with source.open(encoding="utf-8", newline="") as handle:
            reader = csv.reader(handle)
            expected = ["date", "type", "category", "amount", "memo", "tags"]
            if next(reader, None) != expected:
                raise InputError("CSV header does not match the fixed schema", "See README import/export schema")
            for row in reader:
                if len(row) != len(expected):
                    skipped += 1
                    continue
                date_text, type_text, category, amount, memo, tags = row
                try:
                    self.add(TransactionDraft(date_text, type_text, category, amount, memo, tags))
                    imported += 1
                except InputError:
                    skipped += 1
        return ImportResult(imported, skipped)

    def _require_category(self, category: str) -> None:
        value = parse_category(category)
        if value not in self.store.list_categories():
            raise InputError(f"unknown category: {value}", "Run 'category list' or 'category add'")

    @staticmethod
    def _criteria(selection: ExportSelection) -> SearchCriteria:
        if selection.month is not None:
            parse_month(selection.month)
            year, month_number = (int(part) for part in selection.month.split("-"))
            start = parse_date(f"{selection.month}-01")
            end = parse_date(f"{year + (month_number == 12):04d}-{(month_number % 12) + 1:02d}-01")
            from datetime import timedelta
            return SearchCriteria(date_from=start, date_to=end - timedelta(days=1))
        return SearchCriteria(
            date_from=None if selection.date_from is None else parse_date(selection.date_from),
            date_to=None if selection.date_to is None else parse_date(selection.date_to),
        )
