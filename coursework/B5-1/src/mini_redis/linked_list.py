from dataclasses import dataclass
from typing import Generic, TypeVar

T = TypeVar("T")


@dataclass(slots=True)
class ListNode(Generic[T]):  # noqa: MUTABLE_OK
    """Mutable links are the state of a list node."""

    data: T
    prev: "ListNode[T] | None" = None
    next: "ListNode[T] | None" = None


class DoublyLinkedList(Generic[T]):
    """Own an ordered chain and mutate it through already-known nodes."""

    def __init__(self) -> None:
        self.head: ListNode[T] | None = None
        self.tail: ListNode[T] | None = None
        self._size = 0

    def __len__(self) -> int:
        return self._size

    def insert_front(self, data: T) -> ListNode[T]:
        node = ListNode(data=data, next=self.head)
        if self.head is None:
            self.tail = node
        else:
            self.head.prev = node
        self.head = node
        self._size += 1
        return node

    def insert_back(self, data: T) -> ListNode[T]:
        node = ListNode(data=data, prev=self.tail)
        if self.tail is None:
            self.head = node
        else:
            self.tail.next = node
        self.tail = node
        self._size += 1
        return node

    def remove_front(self) -> T | None:
        if self.head is None:
            return None
        node = self.head
        self.remove_node(node)
        return node.data

    def remove_back(self) -> T | None:
        if self.tail is None:
            return None
        node = self.tail
        self.remove_node(node)
        return node.data

    def remove_node(self, node: ListNode[T]) -> None:
        before = node.prev
        after = node.next
        if before is None:
            self.head = after
        else:
            before.next = after
        if after is None:
            self.tail = before
        else:
            after.prev = before
        node.prev = None
        node.next = None
        self._size -= 1

    def move_to_front(self, node: ListNode[T]) -> None:
        if node is self.head:
            return
        before = node.prev
        after = node.next
        if before is not None:
            before.next = after
        if after is None:
            self.tail = before
        else:
            after.prev = before
        node.prev = None
        node.next = self.head
        if self.head is not None:
            self.head.prev = node
        self.head = node
        if self.tail is None:
            self.tail = node

    def values(self) -> list[T]:
        result: list[T] = []
        current = self.head
        while current is not None:
            result.append(current.data)
            current = current.next
        return result
