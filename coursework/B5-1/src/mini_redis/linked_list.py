"""Implement a doubly linked list with constant-time known-node mutations."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Generic, Iterator, TypeVar

T = TypeVar("T")


@dataclass(eq=False)
class ListNode(Generic[T]):
    """Mutable links are the state of a list node."""

    data: T
    prev: ListNode[T] | None = None
    next: ListNode[T] | None = None


class DoublyLinkedList(Generic[T]):
    """Own an ordered chain and mutate it through already-known nodes."""

    def __init__(self) -> None:
        """Initialize an empty chain."""
        self.head: ListNode[T] | None = None
        self.tail: ListNode[T] | None = None
        self._size: int = 0

    def __len__(self) -> int:
        """Return the number of linked nodes."""
        return self._size

    def insert_front(self, data: T) -> ListNode[T]:
        """Insert a value at the front and return its node."""
        node = ListNode(data=data)
        self._link_front(node)
        self._size += 1
        return node

    def _link_front(self, node: ListNode[T]) -> None:
        node.next = self.head
        if self.head is None:
            self.tail = node
        else:
            self.head.prev = node
        self.head = node

    def insert_back(self, data: T) -> ListNode[T]:
        """Insert a value at the back and return its node."""
        node = ListNode(data=data, prev=self.tail)
        if self.tail is None:
            self.head = node
        else:
            self.tail.next = node
        self.tail = node
        self._size += 1
        return node

    def remove_front(self) -> T | None:
        """Remove and return the front value, if any."""
        if self.head is None:
            return None
        node = self.head
        self.remove_node(node)
        return node.data

    def remove_back(self) -> T | None:
        """Remove and return the back value, if any."""
        if self.tail is None:
            return None
        node = self.tail
        self.remove_node(node)
        return node.data

    def remove_node(self, node: ListNode[T]) -> None:
        """Remove a node known to belong to this chain."""
        self._unlink(node)
        self._size -= 1

    def _unlink(self, node: ListNode[T]) -> None:
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

    def move_to_front(self, node: ListNode[T]) -> None:
        """Move an existing node to the front without replacing it."""
        if node is self.head:
            return
        self._unlink(node)
        self._link_front(node)

    def values(self) -> list[T]:
        """Return the values in front-to-back order."""
        return list(self)

    def __iter__(self) -> Iterator[T]:
        """Iterate over the chain from front to back."""
        current = self.head
        while current is not None:
            yield current.data
            current = current.next
