import ast
import re
from importlib.metadata import metadata, requires

from tests.policy_support import (
    PACKAGE,
    PROJECT_NAME,
    ROOT,
    RUNTIME_DEPENDENCIES,
    dependency_name,
    parse_tree,
    shell_commands,
)


def test_runtime_dependencies_remain_the_exact_narrow_stack() -> None:
    # Given
    dependencies = requires(PROJECT_NAME)
    assert dependencies is not None

    # When
    names = {dependency_name(dependency) for dependency in dependencies}

    # Then
    assert len(names) == len(dependencies)
    assert names == RUNTIME_DEPENDENCIES


def test_models_contain_only_the_standalone_book_entity() -> None:
    # Given
    model_paths = tuple(sorted((PACKAGE / "models").glob("*.py")))
    model_files = {path.name for path in model_paths}
    model_trees = {path.name: parse_tree(path) for path in model_paths}
    tree = model_trees["book.py"]
    book_class = next(
        node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Book"
    )

    # When
    mapped_fields = {
        node.target.id
        for node in book_class.body
        if isinstance(node, ast.AnnAssign)
        and isinstance(node.target, ast.Name)
        and isinstance(node.annotation, ast.Subscript)
        and isinstance(node.annotation.value, ast.Name)
        and node.annotation.value.id == "Mapped"
    }
    entity_classes = {
        node.name
        for name, model_tree in model_trees.items()
        if name != "base.py"
        for node in model_tree.body
        if isinstance(node, ast.ClassDef)
    }
    relationship_apis = {
        alias.name
        for model_tree in model_trees.values()
        for node in ast.walk(model_tree)
        if isinstance(node, ast.ImportFrom)
        for alias in node.names
        if alias.name in {"ForeignKey", "ForeignKeyConstraint", "Relationship", "relationship"}
    }

    # Then
    assert model_files == {"__init__.py", "base.py", "book.py"}
    assert entity_classes == {"Book"}
    assert mapped_fields == {"id", "title", "author", "year"}
    assert not relationship_apis


def test_readme_documents_supported_setup_order() -> None:
    # Given
    readme = (ROOT / "README.md").read_text()
    requires_python = metadata(PROJECT_NAME).get("Requires-Python")
    assert requires_python is not None
    required_version = re.search(r"\d+\.\d+", requires_python)
    assert required_version is not None

    # When
    documented_versions = set(re.findall(r"\bPython\s+(\d+\.\d+)\b", readme))
    commands = tuple(shell_commands(readme))
    sync_position = next(
        index for index, command in enumerate(commands) if command[:2] == ("uv", "sync")
    )
    server_position = next(index for index, command in enumerate(commands) if "uvicorn" in command)

    # Then
    assert required_version.group() in documented_versions
    assert sync_position < server_position
