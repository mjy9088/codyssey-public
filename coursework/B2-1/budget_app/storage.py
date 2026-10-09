from __future__ import annotations

import json
import os
from collections.abc import Callable, Iterable, Iterator
from pathlib import Path
from typing import Final, TypeAlias

from .errors import DataError, InputError
from .models import Money, Transaction, parse_category, parse_month

DEFAULT_CATEGORIES: Final = ("food", "transport", "housing", "salary", "health", "other")
JsonValue: TypeAlias = None | bool | int | float | str | list["JsonValue"] | dict[str, "JsonValue"]


class LedgerStore:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir
        self.transactions_path = data_dir / "transactions.jsonl"
        self.categories_path = data_dir / "categories.json"
        self.budgets_path = data_dir / "budgets.json"

    def initialize(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        if not self.transactions_path.exists():
            self.transactions_path.touch(mode=0o600)
        if not self.categories_path.exists():
            self._write_json_atomic(self.categories_path, list(DEFAULT_CATEGORIES))
        if not self.budgets_path.exists():
            self._write_json_atomic(self.budgets_path, {})

    def iter_transactions(self, *, latest_first: bool = False) -> Iterator[Transaction]:
        self.initialize()
        lines = self._iter_reverse_lines() if latest_first else self._iter_lines()
        try:
            for line_number, line in lines:
                if line.strip():
                    yield Transaction.from_json_line(line, f"transactions.jsonl:{line_number}")
        except UnicodeDecodeError as error:
            raise DataError("transactions.jsonl", "file is not valid UTF-8") from error

    def upsert(self, transaction: Transaction, *, require_existing: bool) -> bool:
        found = False
        inserted = False

        def merged() -> Iterator[Transaction]:
            nonlocal found, inserted
            for current in self.iter_transactions():
                if current.id == transaction.id:
                    found = True
                    continue
                if not inserted and current.sort_key > transaction.sort_key:
                    inserted = True
                    yield transaction
                yield current
            if not inserted:
                yield transaction

        self.replace_transactions(merged(), commit=lambda: found or not require_existing)
        return found

    def replace_transactions(
        self,
        transactions: Iterable[Transaction],
        *,
        commit: Callable[[], bool] | None = None,
    ) -> None:
        temporary = self.transactions_path.with_suffix(".jsonl.tmp")
        self.initialize()
        try:
            with temporary.open("w", encoding="utf-8", newline="\n") as handle:
                for transaction in transactions:
                    handle.write(transaction.to_json_line() + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            if commit is None or commit():
                os.replace(temporary, self.transactions_path)
                self._sync_directory()
        finally:
            temporary.unlink(missing_ok=True)

    def list_categories(self) -> tuple[str, ...]:
        raw = self._read_json(self.categories_path)
        if not isinstance(raw, list):
            raise DataError("categories.json", "expected a JSON string array")
        categories: list[str] = []
        try:
            for item in raw:
                if type(item) is not str:
                    raise DataError("categories.json", "expected a JSON string array")
                categories.append(parse_category(item))
        except InputError as error:
            raise DataError("categories.json", "contains an invalid category") from error
        if len(categories) != len(set(categories)):
            raise DataError("categories.json", "contains duplicate categories")
        return tuple(categories)

    def save_categories(self, categories: Iterable[str]) -> None:
        self._write_json_atomic(self.categories_path, sorted(categories))

    def list_budgets(self) -> dict[str, Money]:
        raw = self._read_json(self.budgets_path)
        if not isinstance(raw, dict):
            raise DataError("budgets.json", "expected a JSON object")
        result: dict[str, Money] = {}
        for month, amount in raw.items():
            if type(amount) is not int or amount <= 0:
                raise DataError("budgets.json", "expected month keys with positive integer values")
            try:
                parse_month(month)
            except InputError as error:
                raise DataError("budgets.json", "contains an invalid month") from error
            result[month] = Money(amount)
        return result

    def save_budgets(self, budgets: dict[str, Money]) -> None:
        self._write_json_atomic(self.budgets_path, budgets)

    def is_active_path(self, path: Path) -> bool:
        candidate = path.resolve()
        return candidate in {
            self.transactions_path.resolve(),
            self.categories_path.resolve(),
            self.budgets_path.resolve(),
        }

    def _read_json(self, path: Path) -> JsonValue:
        self.initialize()
        try:
            with path.open(encoding="utf-8") as handle:
                return json.load(handle)
        except json.JSONDecodeError as error:
            raise DataError(path.name, f"invalid JSON at line {error.lineno}") from error
        except UnicodeDecodeError as error:
            raise DataError(path.name, "file is not valid UTF-8") from error

    def _write_json_atomic(self, path: Path, value: list[str] | dict[str, Money]) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        try:
            with temporary.open("w", encoding="utf-8", newline="\n") as handle:
                json.dump(value, handle, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, path)
            self._sync_directory()
        finally:
            temporary.unlink(missing_ok=True)

    def _sync_directory(self) -> None:
        descriptor = os.open(self.data_dir, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

    def _iter_lines(self) -> Iterator[tuple[int, str]]:
        with self.transactions_path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                yield line_number, line

    def _iter_reverse_lines(self) -> Iterator[tuple[int, str]]:
        with self.transactions_path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            position = handle.tell()
            buffer = b""
            line_number = sum(1 for _ in self._iter_lines())
            at_file_end = True
            while position > 0:
                size = min(8192, position)
                position -= size
                handle.seek(position)
                buffer = handle.read(size) + buffer
                lines = buffer.split(b"\n")
                buffer = lines[0]
                for raw in reversed(lines[1:]):
                    if at_file_end and not raw:
                        at_file_end = False
                        continue
                    at_file_end = False
                    if raw:
                        yield line_number, raw.decode("utf-8")
                    line_number -= 1
            if buffer:
                yield 1, buffer.decode("utf-8")
