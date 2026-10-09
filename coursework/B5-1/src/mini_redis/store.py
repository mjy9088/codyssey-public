import time
from typing import Callable

from mini_redis.hash_map import HashMap
from mini_redis.linked_list import DoublyLinkedList, ListNode
from mini_redis.min_heap import HeapItem, MinHeap


class MiniRedis:
    """Own mutable in-memory state and enforce memory/expiration invariants."""

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._values: HashMap[str] = HashMap()
        self._expires: HashMap[float] = HashMap()
        self._expiry_heap = MinHeap()
        self._lru = DoublyLinkedList[str]()
        self._lru_nodes: HashMap[ListNode[str]] = HashMap()
        self.used_memory = 0
        self.maxmemory = 0
        self.evicted_keys = 0

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
        self.used_memory -= self._entry_size(key, value)
        node = self._lru_nodes.remove(key)
        if node is not None:
            self._lru.remove_node(node)
        self._expires.remove(key)
        return True

    def _purge_expired(self) -> None:
        now = self._clock()
        current = self._expiry_heap.peek()
        while current is not None and current.expire_at <= now:
            record = self._expiry_heap.pop()
            if record is not None:
                active = self._expires.get(record.key)
                if active == record.expire_at:
                    self._remove(record.key)
            current = self._expiry_heap.peek()

    def _evict_to_limit(self) -> None:
        while self.maxmemory > 0 and self.used_memory > self.maxmemory:
            key = self._lru.remove_back()
            if key is None:
                return
            value = self._values.remove(key)
            self._lru_nodes.remove(key)
            self._expires.remove(key)
            stored_value = "" if value is None else value
            self.used_memory -= self._entry_size(key, stored_value)
            self.evicted_keys += 1

    def set(self, key: str, value: str) -> str:
        self._purge_expired()
        new_size = self._entry_size(key, value)
        if self.maxmemory > 0 and new_size > self.maxmemory:
            return "OOM"
        had_old_value = self._values.contains(key)
        old_value = self._values.get(key)
        if had_old_value:
            stored_value = "" if old_value is None else old_value
            self.used_memory -= self._entry_size(key, stored_value)
        self._values.put(key, value)
        self.used_memory += new_size
        self._expires.remove(key)
        self._touch(key)
        self._evict_to_limit()
        return "OK"

    def get(self, key: str) -> str | None:
        self._purge_expired()
        value = self._values.get(key)
        if value is not None:
            self._touch(key)
        return value

    def delete(self, key: str) -> int:
        self._purge_expired()
        return int(self._remove(key))

    def exists(self, key: str) -> int:
        self._purge_expired()
        return int(self._values.contains(key))

    def dbsize(self) -> int:
        self._purge_expired()
        return self._values.size()

    def keys(self) -> list[str]:
        self._purge_expired()
        return self._values.keys()

    def configure_maxmemory(self, byte_limit: int) -> str:
        self._purge_expired()
        self.maxmemory = byte_limit
        self._evict_to_limit()
        return "OK"

    def info_memory(self) -> str:
        self._purge_expired()
        return (
            f"used_memory:{self.used_memory}\n"
            f"maxmemory:{self.maxmemory}\n"
            f"evicted_keys:{self.evicted_keys}"
        )

    def expire(self, key: str, seconds: int) -> int:
        self._purge_expired()
        if not self._values.contains(key):
            return 0
        if seconds <= 0:
            self._remove(key)
            return 1
        expire_at = self._clock() + seconds
        self._expires.put(key, expire_at)
        self._expiry_heap.push(HeapItem(expire_at=expire_at, key=key))
        return 1

    def ttl(self, key: str) -> int:
        self._purge_expired()
        if not self._values.contains(key):
            return -2
        expire_at = self._expires.get(key)
        if expire_at is None:
            return -1
        return max(0, int(expire_at - self._clock()))
