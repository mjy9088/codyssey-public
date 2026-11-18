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
build needs network access for pinned images, packages, and the kernel download.

### VM kernel source

The guest uses Alpine's `virt` kernel from the Linux 6.12 longterm branch. Longterm
support covers maintenance of that kernel branch. Alpine's update repository advances
its package index as newer builds replace older ones, so an exact APK revision can become
unavailable while the branch still receives updates. The VM Dockerfile pins the Alpine
3.22.8 netboot release URL and verifies its kernel with SHA-256. The release archive
retains versioned downloads independently of the package index. When updating the
kernel, update the release URL and checksum together and run `sh scripts/verify.sh vm`
to boot and test it. [Linux longterm releases](https://cdn.kernel.org/releases.html) ·
[Alpine release archive](https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/)

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
