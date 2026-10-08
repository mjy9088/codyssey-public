# AGENTS.md

## Scope

These instructions apply to the entire repository. A more specific `AGENTS.md`
inside a project may add or override instructions for that subtree.

## Repository intent

This is the public working monorepo for the Codyssey AI All-in-One course. Make
changes here only when every committed input and output is safe to publish.
Treat the repository as permanently public, including its full Git history.

## Content boundaries

- Keep original assignment statements, answer keys, restricted course assets,
  credentials, tokens, personal information, and material with uncertain
  publication rights in `codyssey-private`.
- Do not reproduce restricted prompts in comments, tests, fixtures, commit
  messages, screenshots, logs, or generated files.
- Store source, tests, public documentation, reproducible tooling, and sanitized
  evidence here.
- Keep provided analysis archives and task data in the private repository. Public
  tests must use publishable synthetic fixtures rather than restricted inputs.
- Do not track execution logs, run reports, progress journals, traces, or generated
  test results. Prefer rerunnable verification scripts and ignored/CI artifacts.
  Only track an output explicitly required for submission; explain the exception
  and why committing run artifacts is normally poor practice (staleness, repository
  growth, and disclosure risks). Do not retroactively rewrite imported history.
- Git tracks repository-owned inputs and outputs. Do not duplicate that with
  source/output checksum manifests. Dependency locks and external download integrity
  checks remain appropriate.
- Use `codyssey-submit` only as a temporary submission projection. Do not make it
  the source of truth and do not develop independently in it.
- Stop and flag the file instead of committing it when publication safety is
  uncertain.

## Layout

- `environment/`: development and classroom environment tooling.
- `archive/`: imported historical course repositories.
- `docs/`: repository-wide policy and procedures.
- New work: prefer a self-contained directory grouped by course stage or
  project. Preserve the course's canonical capitalization (for example,
  `E1-1`) and use kebab-case for names that have no canonical form.

Do not move an imported subtree or rewrite imported history merely for cosmetic
consistency. Explain any necessary cross-project change in the commit message.

## Working conventions

1. Read the nearest README and any nested `AGENTS.md` before editing.
2. Keep a change within one subtree unless shared policy or tooling requires a
   repository-wide edit.
3. Preserve the existing language, toolchain, formatter, and test conventions
   of the affected project.
4. Run the narrowest relevant checks first, then the project's full documented
   verification when feasible.
5. Do not commit dependency caches, virtual environments, editor state, secrets,
   or generated evidence unless the project explicitly treats that evidence as
   a deliverable.
6. Use English for all authored documentation. Preserve original assignment wording,
   canonical names, and imported historical content when their original form matters.

## Git and submission safety

- Never rewrite or squash the imported archive history without explicit owner
  approval.
- Never add a private repository as a public submodule or remote configuration
  committed to this repository.
- Before publishing, inspect staged paths and diffs and run a secret scan when
  available.
- Build a submission on a temporary branch in `codyssey-submit`, remove every
  out-of-scope path there, and make exactly one preparation commit that contains
  the required deletions and renames. Follow `docs/SUBMISSION_WORKFLOW.md`.
