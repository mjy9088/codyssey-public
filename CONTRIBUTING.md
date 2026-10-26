# Contributing

## Before making a change

Confirm that the material is allowed to be public. If it includes assignment
text, restricted assets, personal information, secrets, or content with unclear
rights, keep it in the private workspace instead.

Read the README and any `AGENTS.md` that applies to the target directory. Each
imported project retains its own tools and verification commands.
Read [the implementation and review standard](docs/QUALITY_STANDARDS.md) as well.
This repository targets maintainable reference implementations, not assessment-only acceptance.

## Change workflow

1. Create a focused branch from the approved current base.
2. Make the smallest coherent change in the relevant subtree.
3. Check responsibility boundaries and affected callers. Preserve documented external
   contracts and keep fixtures, adapters, and domain logic independently owned.
4. Run the project's documented checks and use the changed behavior through its real
   CLI, browser, HTTP, or module surface, including a relevant failure path.
5. Obtain independent review against the quality standard. Test success does not
   override correctness, security, or architecture findings; resolve blockers.
6. Review `git diff --cached` before committing, including generated files and
   screenshots.
7. Write a concise commit message that explains the reason for the change.

Conventional Commit prefixes such as `feat:`, `fix:`, `docs:`, `test:`, and
`chore:` are encouraged but not required for imported historical work.

## Root-level changes

Root files define shared policy or navigation. Avoid placing project-specific
dependencies or configuration at the root unless they intentionally apply to
the entire monorepo.

## Submission

Submit the coursework subtree directly when the destination accepts the monorepo
layout. If a destination requires a standalone root, follow the history-preserving
temporary-worktree procedure in `docs/SUBMISSION_WORKFLOW.md`, or use its archive
procedure when history must be omitted. Do not apply submission-only deletion or
renaming to the normal `public` working tree.
