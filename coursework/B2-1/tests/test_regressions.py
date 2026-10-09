from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from budget_app.cli import run
from budget_app.errors import DataError, InputError
from budget_app.models import ExportSelection, SearchCriteria, TransactionChanges, TransactionDraft
from budget_app.service import LedgerService
from budget_app.storage import LedgerStore


class PersistenceRegressionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.temporary.name)
        self.store = LedgerStore(self.data_dir)
        self.service = LedgerService(self.store)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_list_when_dates_arrive_out_of_order_is_newest_date_then_id(self) -> None:
        # Given transactions added in an order that differs from their dates
        first = self.service.add(TransactionDraft("2026-05-03", "expense", "food", "100", "first", ""))
        second = self.service.add(TransactionDraft("2026-05-01", "expense", "food", "200", "second", ""))
        third = self.service.add(TransactionDraft("2026-05-03", "expense", "food", "300", "third", ""))

        # When listing the durable stream
        listed = list(self.service.search(SearchCriteria(), limit=None))

        # Then date is primary and stable id is the deterministic tie-breaker.
        self.assertEqual([item.id for item in listed], [third.id, first.id, second.id])

    def test_update_when_date_changes_repositions_record_chronologically(self) -> None:
        # Given records stored on consecutive dates
        first = self.service.add(TransactionDraft("2026-05-01", "expense", "food", "100", "", ""))
        second = self.service.add(TransactionDraft("2026-05-02", "expense", "food", "200", "", ""))

        # When the earlier record moves to a later date
        self.service.update(first.id, TransactionChanges(date_text="2026-05-03"))

        # Then the shared persistence order makes it newest.
        listed = list(self.service.search(SearchCriteria(), limit=None))
        self.assertEqual([item.id for item in listed], [first.id, second.id])

    def test_update_when_replacement_is_invalid_preserves_original_file(self) -> None:
        # Given a durable record and its exact bytes
        item = self.service.add(TransactionDraft("2026-05-01", "expense", "food", "100", "", ""))
        original = self.store.transactions_path.read_bytes()

        # When an invalid update fails while the replacement stream is written
        with self.assertRaises(InputError):
            self.service.update(item.id, TransactionChanges(date_text="not-a-date"))

        # Then the active file is unchanged.
        self.assertEqual(self.store.transactions_path.read_bytes(), original)

    def test_persisted_transaction_when_id_is_malformed_is_rejected_at_boundary(self) -> None:
        # Given otherwise valid JSONL with an invalid id
        self.store.initialize()
        record = {
            "id": "BAD",
            "type": "expense",
            "date": "2026-05-01",
            "amount": 100,
            "category": "food",
            "memo": "",
            "tags": [],
        }
        self.store.transactions_path.write_text(json.dumps(record) + "\n", encoding="utf-8")

        # When streamed, then corruption is reported before service id arithmetic.
        with self.assertRaisesRegex(DataError, "invalid transaction record"):
            list(self.store.iter_transactions())

    def test_persisted_transaction_when_text_field_is_not_string_is_rejected(self) -> None:
        # Given persisted JSON that would previously be coerced to text
        self.store.initialize()
        record = {
            "id": "TX-000001",
            "type": "expense",
            "date": 20260501,
            "amount": 100,
            "category": "food",
            "memo": "",
            "tags": [],
        }
        self.store.transactions_path.write_text(json.dumps(record) + "\n", encoding="utf-8")

        # When parsed, then arbitrary JSON types are not string-coerced.
        with self.assertRaises(DataError):
            list(self.store.iter_transactions())

    def test_reverse_stream_when_newest_record_is_corrupt_reports_its_line(self) -> None:
        # Given a valid first record and a corrupt second record in newline-terminated JSONL
        self.store.initialize()
        self.service.add(TransactionDraft("2026-05-01", "expense", "food", "100", "", ""))
        with self.store.transactions_path.open("a", encoding="utf-8") as handle:
            handle.write('{"bad":true}\n')

        # When the newest-first stream parses the corrupt newest record
        # Then its physical line number is reported.
        with self.assertRaisesRegex(DataError, "transactions.jsonl:2"):
            next(self.store.iter_transactions(latest_first=True))

    def test_persisted_metadata_when_domain_values_are_invalid_is_rejected(self) -> None:
        # Given structurally valid metadata with invalid domain values
        self.store.initialize()
        self.store.categories_path.write_text('["food", "food"]\n', encoding="utf-8")
        self.store.budgets_path.write_text('{"not-a-month": true}\n', encoding="utf-8")

        # When each boundary is read, then duplicate categories and invalid budgets fail.
        with self.assertRaises(DataError):
            self.store.list_categories()
        with self.assertRaises(DataError):
            self.store.list_budgets()


class CsvRegressionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.temporary.name)
        self.service = LedgerService(LedgerStore(self.data_dir))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_import_when_header_is_duplicate_or_reordered_rejects_fixed_schema(self) -> None:
        # Given headers containing the right names but the wrong fixed schema
        headers = (
            "date,type,category,amount,tags,memo\n",
            "date,type,category,amount,memo,memo\n",
        )

        # When each file is imported, then its exact ordered header is rejected.
        for index, header in enumerate(headers):
            with self.subTest(header=header):
                source = self.data_dir / f"bad-{index}.csv"
                source.write_text(header, encoding="utf-8")
                with self.assertRaisesRegex(InputError, "header"):
                    self.service.import_csv(source)

    def test_import_when_row_has_missing_or_extra_cells_skips_without_traceback(self) -> None:
        # Given fixed-schema CSV rows with structurally malformed cells
        source = self.data_dir / "rows.csv"
        source.write_text(
            "date,type,category,amount,memo,tags\n"
            "2026-05-01,expense,food,100,memo\n"
            "2026-05-02,expense,food,200,memo,tag,extra\n",
            encoding="utf-8",
        )

        # When imported
        result = self.service.import_csv(source)

        # Then both rows are skipped and no partial records are stored.
        self.assertEqual((result.imported, result.skipped), (0, 2))
        self.assertEqual(list(self.service.store.iter_transactions()), [])

    def test_export_when_target_is_active_store_refuses_without_overwrite(self) -> None:
        # Given an active transaction file
        self.service.add(TransactionDraft("2026-05-01", "expense", "food", "100", "", ""))
        target = self.service.store.transactions_path
        original = target.read_bytes()

        # When export targets that active file, then it fails without changing data.
        with self.assertRaisesRegex(InputError, "active ledger"):
            self.service.export_csv(target, ExportSelection(month="2026-05"))
        self.assertEqual(target.read_bytes(), original)


class CliBoundaryRegressionTests(unittest.TestCase):
    def test_cli_when_input_ends_or_is_interrupted_returns_concise_error(self) -> None:
        # Given interactive input termination signals
        for error in (EOFError(), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__), patch("builtins.input", side_effect=error):
                # When add reaches the command boundary
                result = run(["--data-dir", tempfile.mkdtemp(), "add"])

                # Then termination is represented by a nonzero result, not leaked.
                self.assertNotEqual(result, 0)

    def test_cli_when_jsonl_is_not_utf8_reports_error_without_traceback(self) -> None:
        # Given a data file containing invalid UTF-8
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(__file__).resolve().parents[1]
            store = LedgerStore(Path(temporary))
            store.initialize()
            store.transactions_path.write_bytes(b"\xff\n")

            # When a real CLI process lists it
            result = subprocess.run(
                [sys.executable, "-m", "budget_app", "--data-dir", temporary, "list"],
                cwd=root,
                text=True,
                capture_output=True,
                check=False,
            )

            # Then it exits concisely without a traceback.
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("Traceback", result.stderr)
            self.assertIn("Error:", result.stderr)


if __name__ == "__main__":
    unittest.main()
