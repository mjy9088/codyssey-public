# Mini Redis

This self-contained Python project implements a command-line in-memory key-value store. Its hash
table uses FNV-1a hashing, linked-list bucket chaining, and load-factor resizing. A second doubly
linked list tracks least-recently-used order, and an explicit binary minimum heap schedules expiry.
The cache internals do not use `dict`, `set`, `collections`, `OrderedDict`, or `heapq`.

## Run the REPL

The program supports Python 3.8 and later. Docker Engine and Compose v2 provide a
self-contained runtime.

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

Docker mode runs the deterministic structure, cache, policy, and REPL tests, then drives the
real CLI with piped commands. VM mode boots an x86_64 Alpine kernel under QEMU TCG and runs the
same tests inside the guest. Docker must support `linux/amd64` containers for VM mode. The guest
needs no KVM, privileged container, host socket mount, parent path, or credentials. The first
build needs network access for container images and Alpine packages.

### VM kernel source

The VM build uses `apk` to install the signed `linux-virt` package from Alpine 3.22.
Alpine replaces superseded revisions in its package index, so the build follows the
supported release branch rather than requiring a specific kernel patch or netboot archive.
Run `sh scripts/verify.sh vm` to boot and test the selected kernel.

Memory is the UTF-8 byte length of keys plus values; container and node overhead is intentionally
excluded. Expiry is cleaned from the heap before store operations observe live state.
Superseded heap records are ignored by comparison with the active deadline, and the heap
is rebuilt from live deadlines when stale records accumulate. TTL values use integer
truncation of the remaining monotonic duration.

One internal removal operation owns value, recency-node, active-expiry, and byte-accounting
cleanup. Explicit deletion, expiry, eviction, and replacement use that same transition. An
oversized replacement is rejected before removing the current value, preserving its TTL and state.

The tests check the command table and its outputs, and scan runtime source for prohibited
collections, imports, and calls associated with persistence, networking, and concurrency.
