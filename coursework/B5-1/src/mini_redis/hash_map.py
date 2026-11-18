"""Implement a resizable separate-chaining map for string keys."""

from __future__ import annotations

from dataclasses import dataclass
from typing import ClassVar, Generic, Iterator, TypeVar

from mini_redis.linked_list import DoublyLinkedList, ListNode

V = TypeVar("V")


@dataclass
class Entry(Generic[V]):
    """A bucket entry whose value may be replaced by put."""

    key: str
    value: V


class HashMap(Generic[V]):
    """Map string keys with FNV-1a hashing and linked-list buckets."""

    _LOAD_FACTOR: ClassVar[float] = 0.75

    def __init__(self, initial_capacity: int = 8) -> None:
        """Allocate at least two empty chains."""
        capacity = max(2, initial_capacity)
        self._buckets: list[DoublyLinkedList[Entry[V]]] = [
            DoublyLinkedList() for _ in range(capacity)
        ]
        self._size: int = 0

    @staticmethod
    def _hash(key: str) -> int:
        value = 2_166_136_261
        for byte in key.encode("utf-8"):
            value ^= byte
            value = (value * 16_777_619) & 0xFFFFFFFF
        return value

    def _find(self, key: str) -> ListNode[Entry[V]] | None:
        bucket = self._buckets[self._hash(key) % len(self._buckets)]
        current = bucket.head
        while current is not None:
            if current.data.key == key:
                return current
            current = current.next
        return None

    def put(self, key: str, value: V) -> None:
        """Insert or replace a value, growing the table if needed."""
        existing = self._find(key)
        if existing is not None:
            existing.data.value = value
            return
        index = self._hash(key) % len(self._buckets)
        _ = self._buckets[index].insert_back(Entry(key=key, value=value))
        self._size += 1
        if self._size / len(self._buckets) > self._LOAD_FACTOR:
            self._resize()

    def get(self, key: str) -> V | None:
        """Look up a value, returning None for a missing key."""
        entry = self._find(key)
        return None if entry is None else entry.data.value

    def contains(self, key: str) -> bool:
        """Check whether a key is present."""
        return self._find(key) is not None

    def remove(self, key: str) -> V | None:
        """Remove a key and return its previous value if present."""
        index = self._hash(key) % len(self._buckets)
        bucket = self._buckets[index]
        node = self._find(key)
        if node is None:
            return None
        bucket.remove_node(node)
        self._size -= 1
        return node.data.value

    def keys(self) -> list[str]:
        """Return all keys in bucket order."""
        return [key for key, _ in self.items()]

    def items(self) -> Iterator[tuple[str, V]]:
        """Iterate over key-value pairs in bucket order."""
        for bucket in self._buckets:
            current = bucket.head
            while current is not None:
                yield current.data.key, current.data.value
                current = current.next

    def size(self) -> int:
        """Return the number of stored entries."""
        return self._size

    def _resize(self) -> None:
        old_buckets = self._buckets
        self._buckets = [DoublyLinkedList() for _ in range(len(old_buckets) * 2)]
        self._size = 0
        for bucket in old_buckets:
            current = bucket.head
            while current is not None:
                self.put(current.data.key, current.data.value)
                current = current.next
