from __future__ import annotations

from dataclasses import dataclass


class LedgerError(Exception):
    pass


@dataclass(frozen=True, slots=True)
class InputError(LedgerError):
    reason: str
    hint: str

    def __str__(self) -> str:
        return self.reason


class TransactionIdExhaustedError(InputError):
    pass


@dataclass(frozen=True, slots=True)
class DataError(LedgerError):
    source: str
    reason: str

    def __str__(self) -> str:
        return f"{self.source}: {self.reason}"
