from mini_redis.hash_map import HashMap
from mini_redis.linked_list import DoublyLinkedList
from mini_redis.min_heap import HeapItem, MinHeap


def test_linked_list_supports_constant_time_reordering() -> None:
    linked: DoublyLinkedList[str] = DoublyLinkedList()
    older = linked.insert_back("older")
    linked.insert_front("newer")

    linked.move_to_front(older)

    assert linked.remove_front() == "older"
    assert linked.remove_back() == "newer"


def test_hash_map_resizes_and_preserves_colliding_entries() -> None:
    table: HashMap[int] = HashMap(initial_capacity=2)

    for index in range(40):
        table.put(f"key-{index}", index)

    assert table.size() == 40
    assert table.get("key-17") == 17
    assert table.remove("key-17") == 17
    assert not table.contains("key-17")


def test_min_heap_orders_expirations_and_keys() -> None:
    heap = MinHeap()
    heap.push(HeapItem(expire_at=3.0, key="z"))
    heap.push(HeapItem(expire_at=1.0, key="b"))
    heap.push(HeapItem(expire_at=1.0, key="a"))

    assert heap.pop() == HeapItem(expire_at=1.0, key="a")
    assert heap.peek() == HeapItem(expire_at=1.0, key="b")
    assert heap.size() == 2
