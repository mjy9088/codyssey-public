from __future__ import annotations

import argparse
import csv
import sys
from collections.abc import Callable, Sequence
from functools import wraps
from pathlib import Path
from typing import ParamSpec

from .errors import LedgerError
from .models import ExportSelection, SearchCriteria, Transaction, TransactionChanges, TransactionDraft, parse_date, parse_transaction_id, parse_type
from .service import LedgerService
from .storage import LedgerStore

P = ParamSpec("P")


def command_boundary(function: Callable[P, int]) -> Callable[P, int]:
    @wraps(function)
    def wrapped(*args: P.args, **kwargs: P.kwargs) -> int:
        try:
            return function(*args, **kwargs)
        except LedgerError as error:
            hint = getattr(error, "hint", "Inspect the data file and command options")
            print(f"Error: {error}\nHint: {hint}", file=sys.stderr)
            return 2
        except (OSError, UnicodeError, csv.Error) as error:
            print(f"Error: {error}\nHint: Check paths and file permissions", file=sys.stderr)
            return 3
        except (EOFError, KeyboardInterrupt):
            print("Error: input ended before the command completed\nHint: Run the command again", file=sys.stderr)
            return 130

    return wrapped


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="python -m budget_app", description="Durable personal ledger")
    root.add_argument("--data-dir", type=Path, default=Path("data"), help="persistent data directory")
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("add", help="interactively add a transaction")
    listing = commands.add_parser("list", help="list newest transactions")
    listing.add_argument("--limit", type=positive_int, default=20)
    search = commands.add_parser("search", help="search transactions")
    _add_filters(search)
    search.add_argument("--limit", type=positive_int)
    summary = commands.add_parser("summary", help="show a monthly summary")
    summary.add_argument("--month", required=True)
    summary.add_argument("--top", type=positive_int, default=3)
    budget = commands.add_parser("budget", help="manage budgets").add_subparsers(dest="budget_command", required=True)
    budget_set = budget.add_parser("set", help="set a monthly budget")
    budget_set.add_argument("--month", required=True)
    budget_set.add_argument("--amount", required=True)
    category = commands.add_parser("category", help="manage categories").add_subparsers(dest="category_command", required=True)
    category.add_parser("list", help="list categories")
    category.add_parser("add", help="interactively add a category")
    category_remove = category.add_parser("remove", help="remove an unused category")
    category_remove.add_argument("--name", required=True)
    update = commands.add_parser("update", help="update selected fields by id")
    update.add_argument("--id", required=True)
    for name in ("date", "type", "category", "amount", "memo", "tags"):
        update.add_argument(f"--{name}")
    delete = commands.add_parser("delete", help="delete a transaction")
    delete.add_argument("--id", required=True)
    importing = commands.add_parser("import", help="import fixed-schema CSV")
    importing.add_argument("--from", dest="source", type=Path, required=True)
    exporting = commands.add_parser("export", help="export fixed-schema CSV")
    exporting.add_argument("--out", type=Path, required=True)
    exporting.add_argument("--month")
    exporting.add_argument("--from", dest="date_from")
    exporting.add_argument("--to", dest="date_to")
    return root


def positive_int(raw: str) -> int:
    value = int(raw)
    if value <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return value


def _add_filters(target: argparse.ArgumentParser) -> None:
    target.add_argument("--from", dest="date_from")
    target.add_argument("--to", dest="date_to")
    target.add_argument("--category")
    target.add_argument("--type", dest="transaction_type")
    target.add_argument("--q")
    target.add_argument("--tag")


def _print_transaction(item: Transaction) -> None:
    print(f"{item.id} | {item.date.isoformat()} | {item.type.value} | {item.category} | {item.amount} | {item.memo} | {','.join(item.tags)}")


@command_boundary
def run(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    service = LedgerService(LedgerStore(args.data_dir))
    match args.command:
        case "add":
            item = service.add(TransactionDraft(input("Date (YYYY-MM-DD): "), input("Type (income/expense): "), input("Category: "), input("Amount (positive integer): "), input("Memo (optional): "), input("Tags (comma-separated): ")))
            print(f"Saved id={item.id}")
        case "list":
            for item in service.search(SearchCriteria(), args.limit):
                _print_transaction(item)
        case "search":
            criteria = SearchCriteria(
                date_from=None if args.date_from is None else parse_date(args.date_from),
                date_to=None if args.date_to is None else parse_date(args.date_to),
                category=args.category,
                transaction_type=None if args.transaction_type is None else parse_type(args.transaction_type),
                query=args.q,
                tag=args.tag,
            )
            for item in service.search(criteria, args.limit):
                _print_transaction(item)
        case "summary":
            result = service.summary(args.month, args.top)
            if result.income == 0 and result.expense == 0:
                print("No data")
            else:
                print(f"Income: {result.income}\nExpense: {result.expense}\nBalance: {result.balance}")
                if result.budget_amount is not None:
                    percentage = result.expense * 100 / result.budget_amount
                    print(f"Budget: {result.budget_amount} ({percentage:.1f}% used)")
                    if result.budget_exceeded:
                        print("WARNING: budget exceeded")
                for rank, (category, amount) in enumerate(result.expense_by_category, start=1):
                    print(f"{rank}) {category} {amount}")
        case "budget":
            service.set_budget(args.month, args.amount)
            print(f"Saved budget month={args.month} amount={args.amount}")
        case "category":
            match args.category_command:
                case "list":
                    for category in service.store.list_categories():
                        print(f"- {category}")
                case "add":
                    name = input("Category name: ")
                    if not service.add_category(name):
                        raise LedgerError(f"category already exists: {name}")
                    print(f"Saved category={name}")
                case "remove":
                    if not service.remove_category(args.name):
                        raise LedgerError(f"category not found: {args.name}")
                    print(f"Removed category={args.name}")
        case "update":
            changed = service.update(parse_transaction_id(args.id), TransactionChanges(args.date, args.type, args.category, args.amount, args.memo, args.tags))
            if not changed:
                raise LedgerError(f"transaction not found: {args.id}")
            print(f"Updated id={args.id}")
        case "delete":
            if not service.delete(parse_transaction_id(args.id)):
                raise LedgerError(f"transaction not found: {args.id}")
            print(f"Deleted id={args.id}")
        case "import":
            result = service.import_csv(args.source)
            print(f"Completed imported={result.imported} skipped={result.skipped}")
        case "export":
            count = service.export_csv(args.out, ExportSelection(args.month, args.date_from, args.date_to))
            print(f"Completed {args.out} records={count}")
    return 0
