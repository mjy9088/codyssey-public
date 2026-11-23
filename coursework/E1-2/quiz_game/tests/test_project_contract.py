import ast
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = PROJECT_ROOT / "quiz_game" / "src"
APPLICATION_SOURCES = (
    PROJECT_ROOT / "main.py",
    *sorted((SOURCE_ROOT / "quiz_game").glob("*.py")),
)


class ProjectContractTest(unittest.TestCase):
    def test_application_sources_support_python_310(self) -> None:
        for path in APPLICATION_SOURCES:
            with self.subTest(path=path.relative_to(PROJECT_ROOT)):
                ast.parse(
                    path.read_text(encoding="utf-8"),
                    filename=str(path),
                    feature_version=10,
                )

    def test_application_imports_only_stdlib_and_local_package(self) -> None:
        imported_roots: set[str] = set()
        for path in APPLICATION_SOURCES:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imported_roots.update(alias.name.partition(".")[0] for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                    imported_roots.add(node.module.partition(".")[0])

        allowed = set(sys.stdlib_module_names) | {"quiz_game"}
        self.assertEqual(imported_roots - allowed, set())

    def test_root_script_and_package_module_are_runnable_entrypoints(self) -> None:
        environment = {**os.environ, "PYTHONPATH": str(SOURCE_ROOT)}
        commands = (
            (sys.executable, str(PROJECT_ROOT / "main.py")),
            (sys.executable, "-m", "quiz_game"),
        )
        for command in commands:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                result = subprocess.run(
                    command,
                    input="5\n",
                    text=True,
                    capture_output=True,
                    cwd=directory,
                    env=environment,
                    check=False,
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertGreater(len(result.stdout), 0)
                self.assertEqual(result.stderr, "")
                self.assertFalse((Path(directory) / "state.json").exists())


if __name__ == "__main__":
    unittest.main()
