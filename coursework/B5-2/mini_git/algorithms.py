"""Graph traversal and manual sorting algorithms."""

from collections.abc import Callable, Sequence
from typing import TypeVar

from mini_git.errors import GraphInvariantError
from mini_git.model import Commit, CommitId

T = TypeVar("T")
MINIMUM_SPLIT_SIZE = 2


def merge_sort(items: Sequence[T], key: Callable[[T], tuple[str, ...]]) -> list[T]:
    """Return a stable sorted copy without standard sorting APIs."""
    if len(items) < MINIMUM_SPLIT_SIZE:
        return list(items)
    midpoint = len(items) // 2
    left = merge_sort(items[:midpoint], key)
    right = merge_sort(items[midpoint:], key)
    merged: list[T] = []
    left_index = 0
    right_index = 0
    while left_index < len(left) and right_index < len(right):
        if key(left[left_index]) <= key(right[right_index]):
            merged.append(left[left_index])
            left_index += 1
        else:
            merged.append(right[right_index])
            right_index += 1
    merged.extend(left[left_index:])
    merged.extend(right[right_index:])
    return merged


def topological_commits(commits: Sequence[Commit]) -> list[Commit]:
    """Return every parent before each child."""
    by_id: dict[CommitId, Commit] = {commit.commit_id: commit for commit in commits}
    indegree: dict[CommitId, int] = {commit.commit_id: len(commit.parents) for commit in commits}
    children: dict[CommitId, list[CommitId]] = {commit.commit_id: [] for commit in commits}
    for commit in commits:
        for parent in commit.parents:
            if parent not in by_id:
                raise GraphInvariantError
            children[parent].append(commit.commit_id)
    ready: list[Commit] = merge_sort(
        [commit for commit in commits if indegree[commit.commit_id] == 0],
        key=_commit_order,
    )
    result: list[Commit] = []
    while ready:
        current = ready.pop(0)
        result.append(current)
        for child_id in children[current.commit_id]:
            indegree[child_id] -= 1
            if indegree[child_id] == 0:
                ready.append(by_id[child_id])
        ready = merge_sort(
            ready,
            key=_commit_order,
        )
    if len(result) != len(commits):
        raise GraphInvariantError
    return result


def _commit_order(commit: Commit) -> tuple[str, str]:
    return commit.timestamp.isoformat(), commit.commit_id


def shortest_path(
    commits: Sequence[Commit], start: CommitId, end: CommitId
) -> list[CommitId] | None:
    """Find the lexicographically smallest shortest undirected graph path."""
    adjacency: dict[CommitId, list[CommitId]] = {commit.commit_id: [] for commit in commits}
    for commit in commits:
        for parent in commit.parents:
            adjacency[commit.commit_id].append(parent)
            adjacency[parent].append(commit.commit_id)
    queue: list[list[CommitId]] = [[start]]
    visited = {start}
    while queue:
        path = queue.pop(0)
        current = path[-1]
        if current == end:
            return path
        neighbors = merge_sort(adjacency[current], key=lambda commit_id: (commit_id,))
        for neighbor in neighbors:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append([*path, neighbor])
    return None


def ancestor_ids(commits: Sequence[Commit], start: CommitId) -> list[CommitId]:
    """Return all reachable ancestors once."""
    by_id = {commit.commit_id: commit for commit in commits}
    visited: set[CommitId] = set()
    result: list[CommitId] = []
    stack = list(reversed(by_id[start].parents))
    while stack:
        current = stack.pop()
        if current in visited:
            continue
        visited.add(current)
        result.append(current)
        stack.extend(reversed(by_id[current].parents))
    return result
