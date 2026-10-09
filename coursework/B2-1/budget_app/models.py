from __future__ import annotations

import json
import re
from dataclasses import dataclass, replace
from datetime import date
from enum import StrEnum
from typing import NewType, TypedDict

from .errors import DataError, InputError

TransactionId = NewType("TransactionId", str)
Money = NewType("Money", int)
TRANSACTION_ID_PATTERN = re.compile(r"TX-[0-9]{6}")


class TransactionType(StrEnum):
    INCOME = "income"
    EXPENSE = "expense"


class TransactionJson(TypedDict):
    id: str
    type: str
    date: str
    amount: int
    category: str
    memo: str
    tags: list[str]


@dataclass(frozen=True, slots=True)
class TransactionDraft:
    date_text: str
    type_text: str
    category: str
    amount: str
    memo: str
    tags: str


@dataclass(frozen=True, slots=True)
class TransactionChanges:
    date_text: str | None = None
    type_text: str | None = None
    category: str | None = None
    amount: str | None = None
    memo: str | None = None
    tags: str | None = None


@dataclass(frozen=True, slots=True)
class ExportSelection:
    month: str | None = None
    date_from: str | None = None
    date_to: str | None = None


def parse_date(raw: str) -> date:
    try:
        parsed = date.fromisoformat(raw)
    except ValueError as error:
        raise InputError("date must use YYYY-MM-DD", "Example: 2026-01-15") from error
    if parsed.isoformat() != raw:
        raise InputError("date must use YYYY-MM-DD", "Example: 2026-01-15")
    return parsed


def parse_month(raw: str) -> str:
    try:
        parsed = date.fromisoformat(f"{raw}-01")
    except ValueError as error:
        raise InputError("month must use YYYY-MM", "Example: 2026-01") from error
    if parsed.strftime("%Y-%m") != raw:
        raise InputError("month must use YYYY-MM", "Example: 2026-01")
    return raw


def parse_amount(raw: str) -> Money:
    try:
        value = int(raw)
    except ValueError as error:
        raise InputError("amount must be a whole positive integer", "Example: 15000") from error
    if value <= 0 or str(value) != raw.strip():
        raise InputError("amount must be a whole positive integer", "Example: 15000")
    return Money(value)


def parse_type(raw: str) -> TransactionType:
    try:
        return TransactionType(raw)
    except ValueError as error:
        raise InputError("type must be income or expense", "Choose one exact value") from error


def parse_transaction_id(raw: str) -> TransactionId:
    if TRANSACTION_ID_PATTERN.fullmatch(raw) is None:
        raise InputError("id must use TX- followed by six digits", "Example: TX-000001")
    return TransactionId(raw)


def parse_category(raw: str) -> str:
    value = raw.strip()
    if not value or any(character in value for character in "\r\n,"):
        raise InputError("category must be a non-empty single value", "Use letters, numbers, '-' or '_'")
    return value


def parse_tags(raw: str) -> tuple[str, ...]:
    values = tuple(part.strip() for part in raw.split(",") if part.strip())
    if len(values) != len(set(values)):
        raise InputError("tags must not contain duplicates", "Remove repeated comma-separated tags")
    return values


@dataclass(frozen=True, slots=True)
class Transaction:
    id: TransactionId
    date: date
    type: TransactionType
    category: str
    amount: Money
    memo: str
    tags: tuple[str, ...]

    @classmethod
    def create(
        cls,
        transaction_id: TransactionId,
        draft: TransactionDraft,
    ) -> Transaction:
        return cls(
            id=transaction_id,
            date=parse_date(draft.date_text),
            type=parse_type(draft.type_text),
            category=parse_category(draft.category),
            amount=parse_amount(draft.amount),
            memo=draft.memo.strip(),
            tags=parse_tags(draft.tags),
        )

    @classmethod
    def from_json_line(cls, line: str, source: str = "transaction") -> Transaction:
        try:
            raw = json.loads(line)
            if not isinstance(raw, dict):
                raise TypeError
            identifier = raw["id"]
            date_text = raw["date"]
            type_text = raw["type"]
            category = raw["category"]
            amount = raw["amount"]
            memo = raw["memo"]
            tags = raw["tags"]
            expected_keys = {"id", "type", "date", "amount", "category", "memo", "tags"}
            if set(raw) != expected_keys:
                raise TypeError
            if not all(type(value) is str for value in (identifier, date_text, type_text, category, memo)):
                raise TypeError
            if type(amount) is not int or type(tags) is not list or not all(type(tag) is str for tag in tags):
                raise TypeError
            return cls.create(
                parse_transaction_id(identifier),
                TransactionDraft(date_text, type_text, category, str(amount), memo, ",".join(tags)),
            )
        except (json.JSONDecodeError, KeyError, TypeError, InputError) as error:
            raise DataError(source, "invalid transaction record") from error

    def to_json_line(self) -> str:
        value: TransactionJson = {
            "id": self.id,
            "type": self.type.value,
            "date": self.date.isoformat(),
            "amount": self.amount,
            "category": self.category,
            "memo": self.memo,
            "tags": list(self.tags),
        }
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

    def changed(
        self,
        changes: TransactionChanges,
    ) -> Transaction:
        return replace(
            self,
            date=self.date if changes.date_text is None else parse_date(changes.date_text),
            type=self.type if changes.type_text is None else parse_type(changes.type_text),
            category=self.category if changes.category is None else parse_category(changes.category),
            amount=self.amount if changes.amount is None else parse_amount(changes.amount),
            memo=self.memo if changes.memo is None else changes.memo.strip(),
            tags=self.tags if changes.tags is None else parse_tags(changes.tags),
        )

    @property
    def sort_key(self) -> tuple[date, TransactionId]:
        return self.date, self.id


@dataclass(frozen=True, slots=True)
class SearchCriteria:
    date_from: date | None = None
    date_to: date | None = None
    category: str | None = None
    transaction_type: TransactionType | None = None
    query: str | None = None
    tag: str | None = None

    def matches(self, transaction: Transaction) -> bool:
        return all(
            (
                self.date_from is None or transaction.date >= self.date_from,
                self.date_to is None or transaction.date <= self.date_to,
                self.category is None or transaction.category == self.category,
                self.transaction_type is None or transaction.type == self.transaction_type,
                self.query is None or self.query.casefold() in transaction.memo.casefold(),
                self.tag is None or self.tag in transaction.tags,
            )
        )


@dataclass(frozen=True, slots=True)
class Summary:
    income: int
    expense: int
    balance: int
    expense_by_category: tuple[tuple[str, int], ...]
    budget_amount: int | None
    budget_exceeded: bool


@dataclass(frozen=True, slots=True)
class ImportResult:
    imported: int
    skipped: int
