"""Manage values, memory limits, recency, and expiry for one cache."""

from __future__ import annotations

import math
import time
from dataclasses import dataclass
from typing import Callable

from mini_redis.hash_map import HashMap
from mini_redis.linked_list import DoublyLinkedList, ListNode
from mini_redis.min_heap import HeapItem, MinHeap


@dataclass(frozen=True)
class MemoryInfo:
    """A snapshot of the cache's payload bytes, byte limit, and eviction count."""

    used_memory: int
    maxmemory: int
    evicted_keys: int


class MiniRedis:
    """Own mutable in-memory state and enforce memory/expiration invariants."""

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        """Initialize an empty cache using the supplied monotonic clock."""
        self._clock: Callable[[], float] = clock
        self._values: HashMap[str] = HashMap()
        self._expires: HashMap[float] = HashMap()
        self._expiry_heap: MinHeap = MinHeap()
        self._lru: DoublyLinkedList[str] = DoublyLinkedList()
        self._lru_nodes: HashMap[ListNode[str]] = HashMap()
        self._used_memory: int = 0
        self._maxmemory: int = 0
        self._evicted_keys: int = 0

    @property
    def used_memory(self) -> int:
        """Return the accounted payload bytes."""
        return self._used_memory

    @property
    def maxmemory(self) -> int:
        """Return the payload byte limit, with zero indicating no limit."""
        return self._maxmemory

    @property
    def evicted_keys(self) -> int:
        """Return the number of removals caused by memory pressure."""
        return self._evicted_keys

    @staticmethod
    def _entry_size(key: str, value: str) -> int:
        return len(key.encode("utf-8")) + len(value.encode("utf-8"))

    def _touch(self, key: str) -> None:
        node = self._lru_nodes.get(key)
        if node is None:
            self._lru_nodes.put(key, self._lru.insert_front(key))
        else:
            self._lru.move_to_front(node)

    def _remove(self, key: str) -> bool:
        value = self._values.remove(key)
        if value is None:
            return False
        self._used_memory -= self._entry_size(key, value)
        node = self._lru_nodes.remove(key)
        if node is not None:
            self._lru.remove_node(node)
        _ = self._expires.remove(key)
        return True

    def _purge_expired(self, now: float | None = None) -> None:
        if now is None:
            now = self._clock()
        current = self._expiry_heap.peek()
        while current is not None and current.expire_at <= now:
            record = self._expiry_heap.pop()
            if record is not None:
                active = self._expires.get(record.key)
                if active == record.expire_at:
                    _ = self._remove(record.key)
            current = self._expiry_heap.peek()
        self._compact_expiry_heap()

    def _compact_expiry_heap(self) -> None:
        # Rebuild only when enough obsolete records have accumulated to amortize the work.
        stale_record_threshold = max(64, 2 * self._expires.size())
        if self._expiry_heap.size() <= stale_record_threshold:
            return
        heap = MinHeap()
        for key, deadline in self._expires.items():
            heap.push(HeapItem(expire_at=deadline, key=key))
        self._expiry_heap = heap

    def _evict_to_limit(self) -> None:
        while self.maxmemory > 0 and self.used_memory > self.maxmemory:
            oldest = self._lru.tail
            if oldest is None:
                return
            _ = self._remove(oldest.data)
            self._evicted_keys += 1

    def set(self, key: str, value: str) -> str:
        """Store a value, clearing its previous deadline, or return OOM."""
        self._purge_expired()
        new_size = self._entry_size(key, value)
        if self.maxmemory > 0 and new_size > self.maxmemory:
            return "OOM"
        _ = self._remove(key)
        self._values.put(key, value)
        self._used_memory += new_size
        self._touch(key)
        self._evict_to_limit()
        return "OK"

    def get(self, key: str) -> str | None:
        """Return a live value and refresh its eviction priority."""
        self._purge_expired()
        value = self._values.get(key)
        if value is not None:
            self._touch(key)
        return value

    def delete(self, key: str) -> int:
        """Remove a live key and return the number of keys deleted."""
        self._purge_expired()
        return int(self._remove(key))

    def exists(self, key: str) -> int:
        """Return whether a live key exists as zero or one."""
        self._purge_expired()
        return int(self._values.contains(key))

    def dbsize(self) -> int:
        """Count the live keys."""
        self._purge_expired()
        return self._values.size()

    def keys(self) -> list[str]:
        """Return live keys in unspecified order."""
        self._purge_expired()
        return self._values.keys()

    def configure_maxmemory(self, byte_limit: int) -> str:
        """Set a nonnegative byte limit and evict keys as needed."""
        if byte_limit < 0:
            msg = "memory limit must be nonnegative"
            raise ValueError(msg)
        self._purge_expired()
        self._maxmemory = byte_limit
        self._evict_to_limit()
        return "OK"

    def info_memory(self) -> MemoryInfo:
        """Take a memory snapshot after removing expired keys."""
        self._purge_expired()
        return MemoryInfo(self.used_memory, self.maxmemory, self.evicted_keys)

    def expire(self, key: str, seconds: int) -> int:
        """Schedule a supported duration for a live key or delete it immediately."""
        now = self._clock()
        if seconds > 0:
            try:
                deadline = now + seconds
            except OverflowError as error:
                msg = "expiration deadline is out of range"
                raise ValueError(msg) from error
            if not math.isfinite(deadline):
                msg = "expiration deadline is out of range"
                raise ValueError(msg)
        else:
            deadline = now
        self._purge_expired(now)
        if not self._values.contains(key):
            return 0
        if seconds <= 0:
            _ = self._remove(key)
            return 1
        self._expires.put(key, deadline)
        self._expiry_heap.push(HeapItem(expire_at=deadline, key=key))
        return 1

    def ttl(self, key: str) -> int:
        """Return remaining seconds, or the absent/no-deadline sentinel."""
        now = self._clock()
        self._purge_expired(now)
        if not self._values.contains(key):
            return -2
        expire_at = self._expires.get(key)
        if expire_at is None:
            return -1
        return max(0, int(expire_at - now))
