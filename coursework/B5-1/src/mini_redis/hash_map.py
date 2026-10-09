from dataclasses import dataclass
from typing import Generic, TypeVar

from mini_redis.linked_list import DoublyLinkedList, ListNode

V = TypeVar("V")


@dataclass(slots=True)
class Entry(Generic[V]):  # noqa: MUTABLE_OK
    """A bucket entry whose value may be replaced by put."""

    key: str
    value: V


class HashMap(Generic[V]):
    """Map string keys with FNV-1a hashing and linked-list buckets."""

    _LOAD_FACTOR = 0.75

    def __init__(self, initial_capacity: int = 8) -> None:
        capacity = max(2, initial_capacity)
        self._buckets: list[DoublyLinkedList[Entry[V]]] = [
            DoublyLinkedList() for _ in range(capacity)
        ]
        self._size = 0

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
        existing = self._find(key)
        if existing is not None:
            existing.data.value = value
            return
        index = self._hash(key) % len(self._buckets)
        self._buckets[index].insert_back(Entry(key=key, value=value))
        self._size += 1
        if self._size / len(self._buckets) > self._LOAD_FACTOR:
            self._resize()

    def get(self, key: str) -> V | None:
        entry = self._find(key)
        return None if entry is None else entry.data.value

    def contains(self, key: str) -> bool:
        return self._find(key) is not None

    def remove(self, key: str) -> V | None:
        index = self._hash(key) % len(self._buckets)
        bucket = self._buckets[index]
        node = self._find(key)
        if node is None:
            return None
        bucket.remove_node(node)
        self._size -= 1
        return node.data.value

    def keys(self) -> list[str]:
        result: list[str] = []
        for bucket in self._buckets:
            current = bucket.head
            while current is not None:
                result.append(current.data.key)
                current = current.next
        return result

    def size(self) -> int:
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
