## Summary

Describe the change and the affected subtree.

## Verification

- [ ] I ran the relevant project checks.
- [ ] I reviewed this change against `docs/QUALITY_STANDARDS.md`, not only exercise checks.
- [ ] Entry points, domain invariants, I/O adapters, presentation, and fixtures have clear ownership.
- [ ] I traced actual dependencies and exercised rules without their UI or infrastructure adapters.
- [ ] Shared CSS motion and component states were checked in the computed browser result where relevant.
- [ ] Tests enforce behavior and dependency direction without freezing an incidental module inventory.
- [ ] I inspected affected callers and preserved documented CLI/HTTP/data contracts.
- [ ] I used the changed behavior through its real surface, including a relevant failure path.
- [ ] I named unavailable checks and residual risks instead of implying they passed.
- [ ] Independent review found no unresolved correctness, architecture, or security blockers.
- [ ] The reviewer read the current implementation and challenged the boundaries, not only my summary or passing checks.

Checkpoint commits preserve runnable progress; they do not imply final review approval.
- [ ] I reviewed the staged diff and generated artifacts.
- [ ] This change contains no secrets, personal data, restricted assignment
      text, or other material that should remain in `codyssey-private`.
- [ ] Any submission-only reshaping is kept out of this repository.
