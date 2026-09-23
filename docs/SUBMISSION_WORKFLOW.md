# Submission Workflow

## Principle

Develop and review work in `codyssey-public`. Treat `codyssey-submit` as a
reproducible transport repository containing only what a particular assessment
requires. Submission-only deletion and renaming must not alter the canonical
monorepo layout.

## Prepare a hand-in

1. Confirm the source revision in `codyssey-public` is tested, pushed, and safe
   to publish.
2. Update a local clone of `codyssey-submit` and create a new temporary branch
   named for the assessment and attempt, for example
   `submit/e1-3-2026-09-23`.
3. Copy or export the required public subtree from the exact source revision.
   Record that source commit ID in the preparation commit message.
4. Delete every file that the assessment does not require.
5. Apply only the path or filename changes required by the submission format.
6. Inspect the resulting tree, run its relevant checks, and scan it for secrets
   and restricted content.
7. Create exactly one submission-preparation commit containing the deletions and
   renames. Do not add novel implementation work in this commit.
8. Push the temporary branch and submit the required branch or URL.
9. After the assessment lifecycle ends, delete the temporary branch if it is no
   longer needed. The canonical work remains in `codyssey-public`.

## Preparation commit

Use a message that makes the projection traceable, such as:

```text
chore(submission): prepare E1-3 from codyssey-public@<commit>
```

The commit body should list the source subtree, any required rename, and why
files were excluded. Do not include private assignment text in the message.

## Guardrails

- Never copy content from `codyssey-private` into a public submission unless it
  has first been deliberately sanitized and made canonical in
  `codyssey-public`.
- Never commit credentials, even if the submission branch will be deleted.
- Do not merge the preparation commit back into `codyssey-public`.
- If a fix is discovered during preparation, make and test it in
  `codyssey-public`, then rebuild the submission projection.

