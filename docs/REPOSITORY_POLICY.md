# Repository Policy

## Purpose

The course uses three repositories with deliberately different trust and
lifecycle boundaries. A file belongs in exactly one canonical repository.

| Repository | Visibility | Canonical contents | Not for |
| --- | --- | --- | --- |
| `codyssey-public` | Public | Implementation, tests, public notes, reproducible environments, sanitized evidence | Restricted material or submission-only reshaping |
| `codyssey-private` | Private | Assignment text, restricted references, private notes, credentials, personal data, publication-uncertain material | Public collaboration or a hand-in URL |
| `codyssey-submit` | Public when required | A temporary minimal projection prepared for a specific hand-in | Ongoing development or unique source files |

`codyssey-public` is the source of truth for publishable work. The submission
repository can always be recreated from it plus private, local instructions; it
must not contain work that exists nowhere else.

## Classification rule

Before committing a file, ask whether every part of it may be published
permanently, including metadata and history. If the answer is not clearly yes,
put it in `codyssey-private` or keep it untracked until it can be sanitized.

Examples that must remain private include:

- full or substantial assignment statements and grading rubrics;
- instructor-only examples, answer keys, or licensed course assets;
- access tokens, cookies, credentials, private URLs, and environment secrets;
- names, account details, machine identifiers, and other personal data;
- raw logs, screenshots, or datasets that contain any of the above.

Safe public artifacts commonly include original implementation code, tests,
architecture notes written in original words, dependency lock files,
reproducible development tooling, and deliberately sanitized evidence.

## History is publication

Deleting a file in a later commit does not remove it from Git history. Never
commit restricted data even temporarily. If sensitive material is committed,
stop sharing the repository, rotate any exposed credential, and coordinate a
history rewrite before resuming work.

Imported repositories retain their original commit objects and are joined with
unrelated-history merge commits. A path-relocation commit on each imported
lineage places its current tree below the monorepo directory assigned in the
root README. This preserves provenance while avoiding root-level collisions.

## Operational checks

Before pushing a change:

1. inspect the complete staged diff and staged file list;
2. check generated files, screenshots, logs, and fixtures manually;
3. confirm no assignment text was copied merely to explain a solution;
4. run an available secret scanner and the relevant project checks;
5. verify that private-repository content is neither embedded nor referenced in
   a way that grants unintended access.

## Licensing

Public visibility does not itself grant a license. Do not add third-party or
course material unless its license or permission allows redistribution. A
repository-wide license should be added only after the owner intentionally
chooses one; imported components may have separate terms.

