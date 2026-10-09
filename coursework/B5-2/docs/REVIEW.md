# Review guide

## Automated checks

Run both isolated execution paths from this directory:

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
```

The Docker path runs formatting, linting, strict type checks, unit tests, and a subprocess REPL scenario. The VM path boots an x86_64 Linux kernel under QEMU TCG and runs deterministic graph checks plus the real `main.py` REPL inside the guest. Neither path uses the host Docker socket, KVM, privileged mode, runtime bind mounts, parent-directory files, or real credentials.

## Manual review focus

1. Confirm that normal `LOG` output places every parent before each child, including a two-parent merge.
2. Confirm that `PATH` treats parent links as undirected and uses the lexicographically smallest hash sequence when shortest paths tie.
3. Confirm that message search tokenizes only on whitespace, normalizes case, and reads the keyword index rather than scanning commits.
4. Confirm that author search reads its separate normalized index.
5. Confirm that date and author sorting call the handwritten stable merge sort; no `sorted()` or `list.sort()` is present.
6. Try quoted names/messages, lower-case commands, malformed quotes, missing arguments, unknown branches, and unknown commits.

QEMU and Docker results demonstrate local behavior only. They are not evidence of deployment or external collaboration. Generated logs and run reports should remain untracked because they become stale and duplicate the rerunnable checks.
