"""Repository state and index tests."""

from datetime import UTC, datetime, timedelta

import pytest
from mini_git.repository import Repository


class StepClock:
    """Deterministic mutable clock fixture."""

    def __init__(self) -> None:
        self.current: datetime = datetime(2026, 1, 2, tzinfo=UTC)

    def __call__(self) -> datetime:
        result = self.current
        self.current += timedelta(seconds=1)
        return result


def repository() -> Repository:
    repo = Repository(StepClock())
    repo.initialize("Ada Lovelace")
    return repo


def test_branches_diverge_and_merge_commit_has_two_parents() -> None:
    # Given
    repo = repository()
    root = repo.commit("root")
    repo.branch("feature")
    main_tip = repo.commit("main work")
    repo.switch("feature")
    feature_tip = repo.commit("feature work")

    # When
    merged = repo.merge("main")

    # Then
    assert merged.parents == (feature_tip.commit_id, main_tip.commit_id)
    assert root.commit_id in [commit.commit_id for commit in repo.ancestors(merged.commit_id)]


def test_keyword_search_uses_normalized_whitespace_tokens() -> None:
    # Given
    repo = repository()
    expected = repo.commit("Fix LOGIN flow")
    _ = repo.commit("login-page styling")

    # When
    result = repo.search_keyword("LoGiN")

    # Then
    assert result == [expected]


def test_author_index_returns_authored_commits() -> None:
    # Given
    repo = repository()
    first = repo.commit("one")
    second = repo.commit("two")

    # When / Then
    assert repo.search_author("Ada Lovelace") == [first, second]


def test_duplicate_branch_is_rejected() -> None:
    # Given
    repo = repository()
    repo.branch("feature")

    # When / Then
    with pytest.raises(RuntimeError, match="Branch already exists: feature"):
        repo.branch("feature")


def test_unknown_commit_is_rejected() -> None:
    # Given
    repo = repository()

    # When / Then
    with pytest.raises(RuntimeError, match="Unknown commit: missing"):
        _ = repo.ancestors("missing")


def test_commit_identifiers_do_not_repeat_after_reinitialization() -> None:
    # Given
    repo = Repository(lambda: datetime(2026, 1, 2, tzinfo=UTC))
    repo.initialize("Fixed author")
    first = repo.commit("same metadata")
    second = repo.commit("same metadata")

    # When
    repo.initialize("Fixed author")
    third = repo.commit("same metadata")

    # Then
    assert len({first.commit_id, second.commit_id, third.commit_id}) == 3
