from __future__ import annotations

import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from budget_app.models import ExportSelection, SearchCriteria, Transaction, TransactionChanges, TransactionDraft, TransactionId, parse_amount
from budget_app.service import LedgerService
from budget_app.storage import LedgerStore


class ModelTests(unittest.TestCase):
    def test_amount_when_fractional_minor_unit_rejected(self) -> None:
        # Given a value that cannot be represented as integer minor units
        raw = "12.50"
        # When parsing the value, then a domain error is raised.
        with self.assertRaisesRegex(Exception, "whole positive integer"):
            parse_amount(raw)

    def test_transaction_when_round_tripped_has_same_fields(self) -> None:
        # Given a complete typed transaction
        original = Transaction.create(
            TransactionId("TX-000001"),
            TransactionDraft("2026-01-02", "expense", "food", "1200", "lunch", "meal,work"),
        )
        # When serialized and parsed
        restored = Transaction.from_json_line(original.to_json_line())
        # Then the domain object is preserved.
        self.assertEqual(restored, original)


class StorageAndServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.temporary.name)
        self.store = LedgerStore(self.data_dir)
        self.service = LedgerService(self.store)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_initialization_when_empty_creates_three_persistent_files(self) -> None:
        # Given an empty data directory, when initialized
        self.store.initialize()
        # Then all independent stores exist and default categories are available.
        self.assertEqual(
            {path.name for path in self.data_dir.iterdir()},
            {"transactions.jsonl", "categories.json", "budgets.json"},
        )
        self.assertIn("food", self.store.list_categories())

    def test_search_when_filtered_streams_matching_transactions_latest_first(self) -> None:
        # Given three persisted transactions
        self.service.add(TransactionDraft("2026-01-01", "expense", "food", "100", "a", "meal"))
        self.service.add(TransactionDraft("2026-01-03", "income", "salary", "500", "pay", "work"))
        self.service.add(TransactionDraft("2026-01-02", "expense", "food", "200", "b", "meal"))
        # When the generator is filtered
        found = list(
            self.service.search(SearchCriteria(category="food", tag="meal"), limit=None)
        )
        # Then matching records are yielded in reverse chronological order.
        self.assertEqual([item.amount for item in found], [200, 100])

    def test_update_and_delete_when_ids_exist_rewrite_atomically(self) -> None:
        # Given two records
        first = self.service.add(TransactionDraft("2026-01-01", "expense", "food", "100", "a", ""))
        second = self.service.add(TransactionDraft("2026-01-02", "income", "salary", "900", "b", ""))
        # When one is updated and the other deleted
        updated = self.service.update(first.id, TransactionChanges(amount="150", memo="changed"))
        deleted = self.service.delete(second.id)
        # Then the durable stream contains only the changed record.
        records = list(self.store.iter_transactions())
        self.assertTrue(updated)
        self.assertTrue(deleted)
        self.assertEqual([(item.id, item.amount, item.memo) for item in records], [(first.id, 150, "changed")])
        self.assertFalse((self.data_dir / "transactions.jsonl.tmp").exists())

    def test_summary_when_budget_exceeded_reports_exact_integer_totals(self) -> None:
        # Given income, expenses, and a monthly budget
        self.service.add(TransactionDraft("2026-02-01", "income", "salary", "2000", "", ""))
        self.service.add(TransactionDraft("2026-02-03", "expense", "food", "700", "", ""))
        self.service.add(TransactionDraft("2026-02-04", "expense", "transport", "500", "", ""))
        self.service.set_budget("2026-02", "1000")
        # When summarized
        result = self.service.summary("2026-02", top=2)
        # Then money and budget calculations are deterministic.
        self.assertEqual((result.income, result.expense, result.balance), (2000, 1200, 800))
        self.assertEqual(result.budget_amount, 1000)
        self.assertTrue(result.budget_exceeded)

    def test_csv_when_exported_and_imported_preserves_public_schema(self) -> None:
        # Given one transaction and a bounded export
        self.service.add(TransactionDraft("2026-03-08", "expense", "food", "321", "meal", "one,two"))
        output = self.data_dir / "export.csv"
        exported = self.service.export_csv(output, ExportSelection(month="2026-03"))
        # When imported into an independent store
        other = LedgerService(LedgerStore(self.data_dir / "other"))
        imported = other.import_csv(output)
        records = list(other.store.iter_transactions())
        # Then the fixed schema and values survive.
        with output.open(encoding="utf-8", newline="") as handle:
            header = next(csv.reader(handle))
        self.assertEqual(header, ["date", "type", "category", "amount", "memo", "tags"])
        self.assertEqual((exported, imported.imported, imported.skipped), (1, 1, 0))
        self.assertEqual(records[0].tags, ("one", "two"))

    def test_corrupt_json_when_streamed_fails_with_line_context(self) -> None:
        # Given malformed persistent data
        self.store.initialize()
        (self.data_dir / "transactions.jsonl").write_text('{"bad": true}\n', encoding="utf-8")
        # When read, then the error identifies the source line.
        with self.assertRaisesRegex(Exception, "transactions.jsonl:1"):
            list(self.store.iter_transactions())


class CliEndToEndTests(unittest.TestCase):
    def test_cli_when_driven_across_processes_persists_and_reports_errors(self) -> None:
        # Given an isolated data directory
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(__file__).resolve().parents[1]
            data_dir = Path(temporary)
            base = [sys.executable, "-m", "budget_app", "--data-dir", str(data_dir)]
            # When separate CLI processes mutate and read the ledger
            added = subprocess.run(
                base + ["add"],
                cwd=root,
                input="2026-04-01\nexpense\nfood\n450\nlunch\nmeal\n",
                text=True,
                capture_output=True,
                check=False,
            )
            listed = subprocess.run(base + ["list", "--limit", "1"], cwd=root, text=True, capture_output=True, check=False)
            missing = subprocess.run(base + ["delete", "--id", "TX-999999"], cwd=root, text=True, capture_output=True, check=False)
            # Then state persists and failures are concise with a nonzero exit.
            self.assertEqual(added.returncode, 0, added.stderr)
            self.assertIn("TX-000001", listed.stdout)
            self.assertEqual(missing.returncode, 2)
            self.assertIn("Hint:", missing.stderr)
            self.assertNotIn("Traceback", missing.stderr)


if __name__ == "__main__":
    unittest.main()
