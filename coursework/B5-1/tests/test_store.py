from dataclasses import dataclass

from mini_redis.store import MiniRedis


@dataclass(slots=True)
class ManualClock:
    now: float = 100.0

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


def test_utf8_memory_and_overwrite_reset_ttl() -> None:
    clock = ManualClock()
    store = MiniRedis(clock=clock)
    assert store.set("한", "🙂") == "OK"
    assert store.used_memory == 7
    assert store.expire("한", 20) == 1

    assert store.set("한", "a") == "OK"

    assert store.used_memory == 4
    assert store.ttl("한") == -1


def test_get_refreshes_lru_before_eviction() -> None:
    store = MiniRedis(clock=ManualClock())
    assert store.configure_maxmemory(6) == "OK"
    assert store.set("a", "11") == "OK"
    assert store.set("b", "22") == "OK"
    assert store.get("a") == "11"

    assert store.set("c", "33") == "OK"

    assert store.get("b") is None
    assert store.get("a") == "11"
    assert store.evicted_keys == 1


def test_oversize_write_is_atomic_for_existing_key() -> None:
    clock = ManualClock()
    store = MiniRedis(clock=clock)
    assert store.set("key", "old") == "OK"
    assert store.expire("key", 50) == 1
    assert store.configure_maxmemory(7) == "OK"

    assert store.set("key", "oversize") == "OOM"

    assert store.get("key") == "old"
    assert store.ttl("key") == 50
    assert store.used_memory == 6


def test_expiration_cleanup_handles_stale_heap_records() -> None:
    clock = ManualClock()
    store = MiniRedis(clock=clock)
    assert store.set("session", "data") == "OK"
    assert store.expire("session", 2) == 1
    assert store.expire("session", 10) == 1
    clock.advance(3)

    assert store.get("session") == "data"
    assert store.ttl("session") == 7
    clock.advance(7)
    assert store.dbsize() == 0
    assert store.ttl("session") == -2


def test_delete_cleans_value_lru_and_ttl() -> None:
    clock = ManualClock()
    store = MiniRedis(clock=clock)
    store.set("gone", "value")
    store.expire("gone", 5)

    assert store.delete("gone") == 1
    assert store.delete("gone") == 0
    assert store.used_memory == 0
    assert store.ttl("gone") == -2


def test_empty_value_overwrite_and_eviction_keep_memory_exact() -> None:
    store = MiniRedis(clock=ManualClock())
    assert store.set("empty", "") == "OK"
    assert store.used_memory == 5
    assert store.set("empty", "x") == "OK"
    assert store.used_memory == 6
    assert store.configure_maxmemory(2) == "OK"
    assert store.used_memory == 0
    assert store.evicted_keys == 1
