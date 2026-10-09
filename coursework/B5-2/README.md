# Mini Git

Mini Git is an in-memory educational commit-graph CLI. It implements branches, commits, a two-parent merge, parent-first history, graph traversal, indexed search, and handwritten stable merge sort without invoking Git or graph/sort libraries.

## Run the REPL

Python 3.11 or later:

```sh
uv sync --no-dev
uv run python main.py
```

Or with the pinned container image:

```sh
docker compose run --rm app
```

Commands are case-insensitive. Quote arguments containing spaces.

```text
INIT "Ada Lovelace"
COMMIT "Initial commit"
BRANCH feature
SWITCH feature
COMMIT "Add login flow"
LOG
LOG --sort-by=date
LOG --sort-by=author
SEARCH login
SEARCH --author="Ada Lovelace"
ANCESTORS <commit-hash>
PATH <first-hash> <second-hash>
MERGE main
quit
```

`MERGE` is an optional extension that creates a commit whose ordered parents are the current tip and target tip. Repository state intentionally lasts only for the current process.

## Algorithms and complexity

- Commits are immutable nodes held in a hash map by ID. Branches point to a commit or to no commit before their first change. New commits reference existing nodes, so repository operations cannot introduce a cycle.
- Parent-first `LOG` uses Kahn-style topological traversal. Its ready queue is ordered deterministically with the handwritten merge sort.
- `PATH` uses breadth-first search over parent links treated as undirected edges. Lexically ordered neighbor expansion selects the lexicographically smallest complete hash path among equal shortest paths.
- `ANCESTORS` uses iterative depth-first traversal and a visited set, covering shared merge ancestors once.
- Keyword and author searches use separate inverted indexes. Message tokens are whitespace-split and case-normalized. Lookup is proportional to the result bucket rather than all commits.
- Date/author ordering uses a stable handwritten merge sort: `O(n log n)` time in average and worst cases, plus `O(n)` auxiliary space. Python's `sorted()` and `list.sort()` are not used.

Commit IDs encode a monotonically increasing counter in hexadecimal, padded to at least ten characters. The counter belongs to the repository instance and does not rewind on `INIT`, so identifiers cannot repeat within that instance. These are educational identifiers, not Git content hashes. Injected clocks make timestamps deterministic in tests.

## Verification

This directory is a self-contained build context:

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

The first run downloads digest-pinned base images and exact Python tool versions. Docker mode runs Ruff, BasedPyright, pytest, algorithm edges, and REPL happy/error paths. VM mode packages the same source and Python runtime into an initramfs, boots an x86_64 Alpine kernel under QEMU TCG, then executes deterministic graph checks and `main.py` inside the guest. It does not require KVM, privileged containers, a host Docker socket, bind mounts, private files, or parent-directory context.

See [`docs/REVIEW.md`](docs/REVIEW.md) for reviewer checks. Verification output is intentionally not tracked; rerunnable automation is less stale and less likely to disclose local details than committed run logs.

## Layout

```text
main.py                 REPL entry point
mini_git/model.py       immutable graph node types
mini_git/repository.py  branches, commit map, and inverted indexes
mini_git/algorithms.py  manual sort and graph traversals
mini_git/cli.py         quote-aware command boundary and formatting
tests/                  deterministic unit and subprocess REPL coverage
verify/                 pinned Docker and QEMU guest checks
scripts/verify.sh       docker|vm|all orchestration
```
