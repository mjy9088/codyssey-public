"""Repository state and index tests."""

from dataclasses import FrozenInstanceError
from datetime import UTC, datetime, timedelta
from typing import Never, final

import pytest
from mini_git.model import Commit, CommitId
from mini_git.repository import Repository
from typing_extensions import override


class StepClock:
    """Deterministic mutable clock fixture."""

    def __init__(self) -> None:
        self.current: datetime = datetime(2026, 1, 2, tzinfo=UTC)

    def __call__(self) -> datetime:
        result = self.current
        self.current += timedelta(seconds=1)
        return result


@final
class SequenceClock:
    def __init__(self, timestamps: list[datetime]) -> None:
        self._timestamps = iter(timestamps)

    def __call__(self) -> datetime:
        return next(self._timestamps)


class LookupOnlyCommits(dict[CommitId, Commit]):
    @override
    def values(self) -> Never:
        raise AssertionError


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


def test_commits_are_immutable_value_objects() -> None:
    # Given
    commit = repository().commit("original")

    # When / Then
    mutations = (("message", "changed"), ("parents", (CommitId("other"),)))
    for name, value in mutations:
        with pytest.raises(FrozenInstanceError):
            setattr(commit, name, value)


def test_keyword_and_author_search_read_indexes_without_scanning_commits(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Given
    repo = repository()
    first = repo.commit("Fix login")
    second = repo.commit("Document login")
    commits = {commit.commit_id: commit for commit in repo.log()}
    monkeypatch.setattr(repo, "_commits", LookupOnlyCommits(commits))

    # When / Then
    assert repo.search_keyword("login") == [first, second]
    assert repo.search_author("ada lovelace") == [first, second]


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


def test_log_date_and_author_modes_apply_deterministic_ordering() -> None:
    # Given
    later = datetime(2026, 1, 3, tzinfo=UTC)
    earlier = datetime(2026, 1, 1, tzinfo=UTC)
    repo = Repository(SequenceClock([later, earlier]))
    repo.initialize("ada")
    later_commit = repo.commit("later timestamp")
    earlier_commit = repo.commit("earlier timestamp")

    # When
    by_date = repo.log("date")
    by_author = repo.log("author")

    # Then
    assert by_date == [earlier_commit, later_commit]
    assert by_author == [earlier_commit, later_commit]


def test_path_handles_identity_and_unknown_endpoint_boundaries() -> None:
    # Given
    repo = repository()
    commit = repo.commit("root")

    # When / Then
    assert repo.path(commit.commit_id, commit.commit_id) == [commit.commit_id]
    with pytest.raises(RuntimeError, match="Unknown commit: missing"):
        _ = repo.path("missing", commit.commit_id)
    with pytest.raises(RuntimeError, match="Unknown commit: missing"):
        _ = repo.path(commit.commit_id, "missing")
