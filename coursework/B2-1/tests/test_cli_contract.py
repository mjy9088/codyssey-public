from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class CliContractTests(unittest.TestCase):
    def test_help_is_available_at_root_category_and_category_remove_levels(self) -> None:
        root = Path(__file__).resolve().parents[1]
        commands = (
            (["--help"], ("add", "list", "search", "summary", "budget", "category", "update", "delete", "import", "export")),
            (["category", "--help"], ("add", "list", "remove")),
            (["category", "remove", "--help"], ("--name",)),
        )

        for arguments, expected in commands:
            with self.subTest(arguments=arguments):
                result = subprocess.run(
                    [sys.executable, "-m", "budget_app", *arguments],
                    cwd=root,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                for token in expected:
                    self.assertIn(token, result.stdout)

    def test_category_cli_lifecycle_blocks_removal_while_in_use(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(__file__).resolve().parents[1]
            base = [sys.executable, "-m", "budget_app", "--data-dir", directory]

            added_category = subprocess.run(
                base + ["category", "add"], cwd=root, input="books\n", text=True,
                capture_output=True, check=False,
            )
            listed = subprocess.run(
                base + ["category", "list"], cwd=root, text=True,
                capture_output=True, check=False,
            )
            added_transaction = subprocess.run(
                base + ["add"], cwd=root,
                input="2026-06-01\nexpense\nbooks\n250\nreference\nstudy\n",
                text=True, capture_output=True, check=False,
            )
            blocked = subprocess.run(
                base + ["category", "remove", "--name", "books"], cwd=root,
                text=True, capture_output=True, check=False,
            )
            deleted = subprocess.run(
                base + ["delete", "--id", "TX-000001"], cwd=root,
                text=True, capture_output=True, check=False,
            )
            removed = subprocess.run(
                base + ["category", "remove", "--name", "books"], cwd=root,
                text=True, capture_output=True, check=False,
            )

            self.assertEqual(added_category.returncode, 0, added_category.stderr)
            self.assertIn("- books", listed.stdout)
            self.assertEqual(added_transaction.returncode, 0, added_transaction.stderr)
            self.assertEqual(blocked.returncode, 2)
            self.assertIn("Hint:", blocked.stderr)
            self.assertNotIn("Traceback", blocked.stderr)
            self.assertEqual(deleted.returncode, 0, deleted.stderr)
            self.assertEqual(removed.returncode, 0, removed.stderr)


if __name__ == "__main__":
    unittest.main()
