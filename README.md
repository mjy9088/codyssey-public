# Codyssey AI All-in-One

This repository is the public working monorepo for the Codyssey AI All-in-One
course. It contains material that is safe and useful to publish: source code,
reproducible development environments, engineering notes, tests, and evidence
intended for public submission.

## Repository map

| Path | Purpose |
| --- | --- |
| `environment/codyssey-init/` | Classroom and local development-environment bootstrap |
| `archive/E1-1/` | Imported E1-1 work, with its original Git history |
| `archive/E1-2/` | Imported E1-2 work, with its original Git history |
| `archive/E1-3/` | Imported E1-3 work, with its original Git history |
| `docs/` | Repository policy and submission workflow |

Additional course work should normally be added under a clearly named course or
project directory rather than at the repository root.

## Repository roles

- **This repository (`codyssey-public`)** is the canonical public workspace and
  monorepo.
- **`codyssey-private`** is the canonical home for assignment text, restricted
  course material, credentials, personal data, and anything whose publication
  rights are unclear.
- **[`codyssey-submit`](https://github.com/mjy9088/codyssey-submit)** is a
  disposable, submission-only projection. It is not a development source of
  truth.

Read [the repository policy](docs/REPOSITORY_POLICY.md) before adding content.
For an assessment hand-in, follow [the submission workflow](docs/SUBMISSION_WORKFLOW.md).

## Imported history

The repositories below were imported as unrelated histories. Their existing
commits remain reachable unchanged; a later commit on each lineage relocates its
tree into this monorepo before the lineage is merged.

- [`codyssey-init`](https://github.com/mjy9088/codyssey-init)
- [`E1-1`](https://github.com/mjy90884682/E1-1)
- [`E1-2`](https://github.com/mjy90884682/E1-2)
- [`E1-3`](https://github.com/mjy90884682/E1-3)

Exact source and integration commits are recorded in
[the import manifest](docs/IMPORTS.md).

To inspect all imported lineages:

```bash
git log --graph --oneline --decorate --all
```

## Working here

Keep changes scoped to one project when practical, run the checks documented in
that project's README, and never copy restricted assignment content into an
issue, commit, test fixture, screenshot, or generated artifact. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the normal workflow.
