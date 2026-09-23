# Contributing

## Before making a change

Confirm that the material is allowed to be public. If it includes assignment
text, restricted assets, personal information, secrets, or content with unclear
rights, keep it in `codyssey-private` instead.

Read the README and any `AGENTS.md` that applies to the target directory. Each
imported project retains its own tools and verification commands.

## Change workflow

1. Create a focused branch from `main`.
2. Make the smallest coherent change in the relevant subtree.
3. Run that project's documented tests, linters, or verification scripts.
4. Review `git diff --cached` before committing, including generated files and
   screenshots.
5. Write a concise commit message that explains the reason for the change.

Conventional Commit prefixes such as `feat:`, `fix:`, `docs:`, `test:`, and
`chore:` are encouraged but not required for imported historical work.

## Root-level changes

Root files define shared policy or navigation. Avoid placing project-specific
dependencies or configuration at the root unless they intentionally apply to
the entire monorepo.

## Submission

Do not trim this repository for a submission and do not merge submission-only
renames back into it. Produce the hand-in from the separate `codyssey-submit`
repository by following `docs/SUBMISSION_WORKFLOW.md`.

