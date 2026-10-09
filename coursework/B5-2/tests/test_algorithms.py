"""Pure algorithm behavior tests."""

from datetime import UTC, datetime, timedelta

from mini_git.algorithms import ancestor_ids, merge_sort, shortest_path, topological_commits
from mini_git.model import Commit, CommitId

BASE = datetime(2026, 1, 2, tzinfo=UTC)


def node(name: str, seconds: int, *parents: str, author: str = "Ada") -> Commit:
    return Commit(
        commit_id=CommitId(name),
        message=name,
        author=author,
        timestamp=BASE + timedelta(seconds=seconds),
        parents=tuple(CommitId(parent) for parent in parents),
    )


def test_merge_sort_is_stable_and_does_not_mutate_input() -> None:
    # Given
    original = [node("c", 2, author="B"), node("a", 1), node("b", 0, author="B")]

    # When
    result = merge_sort(original, key=lambda commit: (commit.author,))

    # Then
    assert [item.commit_id for item in result] == ["a", "c", "b"]
    assert [item.commit_id for item in original] == ["c", "a", "b"]


def test_topological_log_places_every_parent_before_its_children() -> None:
    # Given
    commits = [node("root", 0), node("z", 1, "root"), node("a", 2, "root"), node("m", 3, "z", "a")]

    # When
    result = topological_commits(commits)

    # Then
    positions = {commit.commit_id: index for index, commit in enumerate(result)}
    assert positions[CommitId("root")] < positions[CommitId("z")] < positions[CommitId("m")]
    assert positions[CommitId("root")] < positions[CommitId("a")] < positions[CommitId("m")]


def test_shortest_path_chooses_lexicographically_smallest_complete_path() -> None:
    # Given: s-a-z-t and s-b-c-t are equal-length undirected paths.
    commits = [
        node("s", 0),
        node("a", 1, "s"),
        node("b", 2, "s"),
        node("z", 3, "a"),
        node("c", 4, "b"),
        node("t", 5, "z", "c"),
    ]

    # When
    result = shortest_path(commits, CommitId("s"), CommitId("t"))

    # Then
    assert result == ["s", "a", "z", "t"]


def test_shortest_path_returns_none_for_disconnected_nodes() -> None:
    # Given
    commits = [node("a", 0), node("b", 1)]

    # When / Then
    assert shortest_path(commits, CommitId("a"), CommitId("b")) is None


def test_ancestors_cover_merge_graph_without_duplicates() -> None:
    # Given
    commits = [node("r", 0), node("a", 1, "r"), node("b", 2, "r"), node("m", 3, "a", "b")]

    # When
    result = ancestor_ids(commits, CommitId("m"))

    # Then
    assert result == ["a", "r", "b"]
