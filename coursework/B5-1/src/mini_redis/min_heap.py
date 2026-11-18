"""Implement an array-backed binary minimum heap for expiry records."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, order=True)
class HeapItem:
    """An expiry candidate ordered by deadline and then by key."""

    expire_at: float
    key: str


class MinHeap:
    """Store expiration records in an array-backed complete binary tree."""

    def __init__(self) -> None:
        """Initialize an empty heap."""
        self._items: list[HeapItem] = []

    def push(self, item: HeapItem) -> None:
        """Insert an expiry candidate and restore heap order."""
        self._items.append(item)
        self._heapify_up(len(self._items) - 1)

    def pop(self) -> HeapItem | None:
        """Remove the smallest candidate, if any."""
        if not self._items:
            return None
        root = self._items[0]
        final = self._items.pop()
        if self._items:
            self._items[0] = final
            self._heapify_down(0)
        return root

    def peek(self) -> HeapItem | None:
        """Return the smallest candidate without removing it."""
        return None if not self._items else self._items[0]

    def size(self) -> int:
        """Return the number of queued candidates."""
        return len(self._items)

    def _heapify_up(self, index: int) -> None:
        while index > 0:
            parent = (index - 1) // 2
            if self._items[parent] <= self._items[index]:
                return
            self._items[parent], self._items[index] = (
                self._items[index],
                self._items[parent],
            )
            index = parent

    def _heapify_down(self, index: int) -> None:
        length = len(self._items)
        while True:
            left = index * 2 + 1
            right = left + 1
            smallest = index
            if left < length and self._items[left] < self._items[smallest]:
                smallest = left
            if right < length and self._items[right] < self._items[smallest]:
                smallest = right
            if smallest == index:
                return
            self._items[index], self._items[smallest] = (
                self._items[smallest],
                self._items[index],
            )
            index = smallest
