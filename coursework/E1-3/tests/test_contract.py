import ast
import json
import pkgutil
import sys
import sysconfig
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = PROJECT_ROOT / "main.py"
DATA_PATH = PROJECT_ROOT / "data.json"


class BundledDataContractTest(unittest.TestCase):
    def test_required_keys_and_matrix_sizes_are_complete(self) -> None:
        data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
        required_sizes = (5, 13, 25)
        self.assertEqual(set(data), {"filters", "patterns"})
        self.assertEqual(set(data["filters"]), {f"size_{size}" for size in required_sizes})
        self.assertEqual(
            set(data["patterns"]),
            {f"size_{size}_{label}" for size in required_sizes for label in ("cross", "x")},
        )

        for size in required_sizes:
            filters = data["filters"][f"size_{size}"]
            self.assertEqual(set(filters), {"cross", "x"})
            for matrix in filters.values():
                self.assertEqual(len(matrix), size)
                self.assertTrue(all(len(row) == size for row in matrix))
            for label, expected in (("cross", "+"), ("x", "x")):
                case = data["patterns"][f"size_{size}_{label}"]
                self.assertEqual(set(case), {"input", "expected"})
                self.assertEqual(case["expected"], expected)
                self.assertEqual(len(case["input"]), size)
                self.assertTrue(all(len(row) == size for row in case["input"]))


class SourcePolicyTest(unittest.TestCase):
    def test_application_is_python_38_compatible_and_stdlib_only(self) -> None:
        source = SOURCE_PATH.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(SOURCE_PATH), feature_version=8)
        imported_roots = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported_roots.update(alias.name.partition(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                imported_roots.add(node.module.partition(".")[0])

        standard_library = set(sys.builtin_module_names)
        standard_library.update(
            module.name
            for module in pkgutil.iter_modules([sysconfig.get_paths()["stdlib"]])
        )
        standard_library.add("__future__")
        self.assertEqual(imported_roots - standard_library, set())

    def test_mac_accumulates_products_with_nested_explicit_loops(self) -> None:
        tree = ast.parse(SOURCE_PATH.read_text(encoding="utf-8"), filename=str(SOURCE_PATH))
        mac_function = next(
            node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "mac"
        )
        outer_loops = [node for node in mac_function.body if isinstance(node, ast.For)]
        self.assertEqual(len(outer_loops), 1)
        inner_loops = [node for node in outer_loops[0].body if isinstance(node, ast.For)]
        self.assertEqual(len(inner_loops), 1)
        accumulations = [node for node in inner_loops[0].body if isinstance(node, ast.AugAssign)]
        self.assertEqual(len(accumulations), 1)
        accumulation = accumulations[0]
        self.assertIsInstance(accumulation.target, ast.Name)
        self.assertEqual(accumulation.target.id, "score")
        self.assertIsInstance(accumulation.op, ast.Add)
        self.assertIsInstance(accumulation.value, ast.BinOp)
        self.assertIsInstance(accumulation.value.op, ast.Mult)


if __name__ == "__main__":
    unittest.main()
