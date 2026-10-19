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


def test_expired_get_removes_key_without_refreshing_survivor_recency() -> None:
    clock = ManualClock()
    store = MiniRedis(clock=clock)
    assert store.configure_maxmemory(6) == "OK"
    assert store.set("a", "1") == "OK"
    assert store.set("b", "2") == "OK"
    assert store.set("c", "3") == "OK"
    assert store.expire("b", 1) == 1
    clock.advance(1)

    assert store.get("b") is None
    assert store.set("d", "4") == "OK"
    assert store.set("e", "5") == "OK"

    assert store.exists("a") == 0
    assert store.exists("c") == 1
    assert store.used_memory == 6


def test_stale_expiry_record_does_not_remove_overwritten_value() -> None:
    clock = ManualClock()
    store = MiniRedis(clock=clock)
    assert store.set("key", "old") == "OK"
    assert store.expire("key", 2) == 1
    assert store.set("key", "new") == "OK"
    clock.advance(2)

    assert store.get("key") == "new"
    assert store.ttl("key") == -1


def test_zero_maxmemory_restores_unlimited_writes() -> None:
    store = MiniRedis(clock=ManualClock())
    assert store.configure_maxmemory(2) == "OK"
    assert store.set("a", "1") == "OK"
    assert store.configure_maxmemory(0) == "OK"

    assert store.set("long", "value") == "OK"

    assert store.exists("a") == 1
    assert store.exists("long") == 1
    assert store.maxmemory == 0


def test_expire_missing_and_nonpositive_deadlines_clean_state() -> None:
    store = MiniRedis(clock=ManualClock())
    assert store.expire("missing", 10) == 0
    assert store.set("zero", "value") == "OK"
    assert store.expire("zero", 0) == 1
    assert store.set("negative", "value") == "OK"

    assert store.expire("negative", -1) == 1

    assert store.get("zero") is None
    assert store.get("negative") is None
    assert store.ttl("zero") == -2
    assert store.ttl("negative") == -2
    assert store.used_memory == 0
    assert store.configure_maxmemory(2) == "OK"
    assert store.set("a", "1") == "OK"
    assert store.set("b", "2") == "OK"
    assert store.exists("a") == 0
    assert store.exists("b") == 1
    assert store.used_memory == 2


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
