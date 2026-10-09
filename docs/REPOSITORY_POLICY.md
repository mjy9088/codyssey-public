# Repository Policy

## Purpose

The public monorepo and the private workspace have deliberately different trust
boundaries. A file belongs in exactly one canonical location.

| Location | Visibility | Canonical contents | Not for |
| --- | --- | --- | --- |
| `codyssey-public` | Public | Implementation, tests, public notes, reproducible environments, explicitly required sanitized deliverables | Restricted material or submission-only reshaping |
| Private workspace | Private | Assignment text, restricted references, private notes, credentials, personal data, publication-uncertain material | Public collaboration or a hand-in URL |

`codyssey-public` is the source of truth for publishable work. Any temporary
submission export must be reproducible from a reviewed public revision and must
not become the only copy of implementation work.

## Classification rule

Before committing a file, ask whether every part of it may be published
permanently, including metadata and history. If the answer is not clearly yes,
put it in the private workspace or keep it untracked until it can be sanitized.

Examples that must remain private include:

- full or substantial assignment statements and grading rubrics;
- instructor-only examples, answer keys, or licensed course assets;
- access tokens, cookies, credentials, private URLs, and environment secrets;
- names, account details, machine identifiers, and other personal data;
- raw logs, screenshots, or datasets that contain any of the above.

Safe public artifacts commonly include original implementation code, tests,
architecture notes written in original words, dependency lock files,
and reproducible development tooling.

Each directory under `coursework/` must remain usable as a standalone project.
Keep image build contexts within that subtree, pin external images and
dependencies, and use publishable deterministic fixtures instead of supplied
task data or real credentials.

Do not track execution logs, run reports, traces, progress journals, or generated
test results. Prefer rerunnable checks and ignored or CI artifacts. Track a
generated output only when the assessment explicitly requires it, and document
why that exception is necessary. Do not add checksum or commit inventories for
repository-owned files: Git already records their content and history. Dependency
locks and integrity pins for external downloads remain appropriate.

## History is publication

Deleting a file in a later commit does not remove it from Git history. Never
commit restricted data even temporarily. If sensitive material is committed,
stop sharing the repository, rotate any exposed credential, and coordinate a
history rewrite before resuming work.

Imported repositories retain their original commit objects. Preserve historical
archive files and history; use the Git graph when provenance needs inspection.

## Operational checks

Before pushing a change:

1. inspect the complete staged diff and staged file list;
2. check generated files, screenshots, logs, and fixtures manually;
3. confirm no assignment text was copied merely to explain a solution;
4. run an available secret scanner and the relevant project checks;
5. verify that private-repository content is neither embedded nor referenced in
   a way that grants unintended access.

Pushing or deploying is a separate operation that requires an explicitly
approved destination. Local verification is not evidence of remote publication
or deployment.

## Licensing

Public visibility does not itself grant a license. Do not add third-party or
course material unless its license or permission allows redistribution. A
repository-wide license should be added only after the owner intentionally
chooses one; imported components may have separate terms.
