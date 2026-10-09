# Review guide

## Automated review

Run `sh scripts/verify.sh all`. Docker mode must end with `DOCKER-VERIFY-SUCCESS`; QEMU mode must
show the guest kernel line, eleven `PASS` lines, `VM-TEST-SUCCESS`, and `VM-VERIFY-SUCCESS`. The script
returns nonzero when a test, CLI assertion, image build, guest marker, or Compose command fails.

## Manual REPL review

Run `docker compose run --rm mini-redis` and try:

```text
CONFIG SET maxmemory 10
SET first 1
SET second 22
GET first
INFO memory
EXPIRE first 5
TTL first
SET first replacement
TTL first
quit
```

Check quoted values, malformed quotes, unknown commands, missing arguments, negative memory limits,
oversized UTF-8 entries, overwrite memory accounting, expiry refresh, immediate expiry, empty keys,
and lowering the memory limit after inserts.

## Code inspection

- `linked_list.py`: nodes expose `prev`, `next`, and `data`; known-node insert/remove/move operations
  only relink neighboring nodes.
- `hash_map.py`: FNV-1a is implemented directly, collisions use linked-list buckets, and capacity
  doubles above a 0.75 load factor.
- `min_heap.py`: push/pop use explicit parent/child indexing and heapify operations; `heapq` is absent.
- `store.py`: successful reads touch LRU order, every deletion updates all active structures, stale
  expiry records cannot delete refreshed keys, and a single oversize write returns OOM before mutation.
- `cli.py`: command matching is explicit and input crosses one `shlex` boundary without `eval`.

Runtime logs and test reports are deliberately not tracked: they become stale, duplicate rerunnable
automation, and may disclose local details. Reviewers should rerun the scripts for current evidence.
