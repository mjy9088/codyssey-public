# Mini Redis

This self-contained Python project implements a command-line in-memory key-value store. Its hash
table uses FNV-1a hashing, linked-list bucket chaining, and load-factor resizing. A second doubly
linked list tracks least-recently-used order, and an explicit binary minimum heap schedules expiry.
The cache internals do not use `dict`, `set`, `collections`, `OrderedDict`, or `heapq`.

## Run the REPL

Only Docker Engine and Compose v2 are required:

```sh
docker compose run --rm mini-redis
```

The commands are `SET`, `GET`, `DEL`, `EXISTS`, `DBSIZE`, `KEYS`, `CONFIG SET maxmemory`,
`INFO memory`, `EXPIRE`, and `TTL`. Values may be unquoted single tokens or shell-style quoted
strings. Enter `exit` or `quit` to leave. Parsing uses `shlex`; input is never evaluated as Python.

## Verify

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

Docker mode runs eleven deterministic structure, cache, boundary, and REPL scenarios, then drives the
real CLI with piped commands. VM mode boots an x86_64 Alpine kernel under QEMU TCG and runs the same
Python tests inside the guest. It needs no KVM, privileged container, host socket mount, parent path,
or credentials. The first build needs network access for pinned images and exact Alpine packages.

Memory is the UTF-8 byte length of keys plus values; container and node overhead is intentionally
excluded. Expiry is lazily cleaned from the heap whenever a command observes global state. Repeated
`EXPIRE` calls leave stale heap records that are safely ignored by comparison with the active expiry.
TTL values use integer truncation of the injected monotonic clock.

Local Docker/QEMU execution demonstrates only this implementation in those environments. It is not
evidence of a production Redis deployment, persistence, networking, concurrency, or compatibility
beyond the documented commands.

See [the review guide](docs/REVIEW.md) for boundary scenarios and implementation inspection points.
