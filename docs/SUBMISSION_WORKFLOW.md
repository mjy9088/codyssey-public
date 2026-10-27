# Submission Workflow

## Principle

Develop and review work in this monorepo. Submit the canonical coursework subtree
unchanged when the approved destination accepts it. When a destination requires
the coursework at its repository root, create the submission commit in a
disposable worktree; never reshape the normal `public` working tree. A
history-free archive is available only when the destination must not receive the
public monorepo history.

## Prepare a hand-in

1. Read the selected project's README and applicable `AGENTS.md`.
2. Verify the exact public revision with the project's documented checks.
3. Inspect the selected subtree for secrets, restricted material, generated run
   artifacts, and files outside the assessment scope.
4. Submit that subtree directly if its layout is accepted.
5. When a standalone root and Git history are required, use the disposable
   worktree procedure below.
6. When a standalone root without history is required, use the archive procedure
   below.
7. Re-run the relevant checks against the prepared tree when its layout changed.
8. Transfer the result only to the explicitly approved destination. Local
   preparation does not demonstrate a push, publication, or deployment.

## History-preserving standalone branch

Use `scripts/publish-coursework.sh` when the approved destination requires both a
standalone repository root and the public monorepo history. The script resolves a
local committed revision, verifies that the selected path is a directory in that
revision, creates a detached temporary worktree, removes every tracked path, moves
the selected coursework subtree to the repository root, and creates one
submission-layout commit. It never applies those deletion or move operations to
the normal working tree.

Record the verified source commit and coursework identifier, then run the script
through `sh`:

```sh
revision=$(git rev-parse --verify HEAD)
coursework_id=YOUR_COURSEWORK_ID
sh scripts/publish-coursework.sh --source "$revision" \
  "$coursework_id"
```

`--source` accepts any commit already available in the local repository and
defaults to the local `HEAD`. The script does not fetch, so the resolved source is
independent of later remote changes and preparation performs no network access.
Uncommitted and staged working-tree changes are not included, and the source
working tree and its refs are not modified.

The destination defaults to
`https://github.com/mjy9088/codyssey-submit.git` and the destination branch
defaults to `main`. Pass `DESTINATION` and, if needed, `TARGET_BRANCH` after the
coursework identifier to override those defaults.

The script displays the prepared commit and its root entries, then asks for
confirmation on the terminal. Answering `y` force-pushes the prepared commit;
pressing Enter or answering anything else cancels without changing the
destination. With no interactive terminal, the script only prepares and reports
the commit. A confirmed run overwrites a diverged destination branch, so inspect
the displayed destination and branch before confirming.

Exercise the local preparation, validation, force-push confirmation, and cleanup
paths with synthetic repositories and a simulated push:

```sh
sh tests/publish-coursework-test.sh
```

The destination's tip contains only the selected coursework files, but its
parent commits retain the complete public monorepo history. Therefore this
method is suitable only when the public history reachable from the selected
source revision is acceptable at the destination.

The script intentionally creates the submission-layout commit in a disposable
worktree. Make fixes in the canonical coursework subtree, verify and commit them
on `public`, and then run the publication procedure again.

## History-free standalone archive

Use an archive instead when the destination must not receive any Git history:

```sh
revision=$(git rev-parse --verify HEAD)
coursework_id=YOUR_COURSEWORK_ID
subtree=coursework/$coursework_id
staging=$(mktemp -d)
git archive "$revision" -- "$subtree" \
  | tar -x -C "$staging" --strip-components=2
```

Replace the example subtree with the project being submitted. Record the source
revision outside the exported tree or in destination metadata if traceability is
required; do not add a repository status or provenance inventory. This output
contains files only and cannot preserve commits.

## Guardrails

- Never copy content from the private workspace into a public submission unless
  it has first been deliberately sanitized and made canonical here.
- Never include credentials, private URLs, restricted assignment text, supplied
  data, or private evidence in an export.
- Do not merge submission-only deletions or renames back into this monorepo.
- If a fix is discovered during preparation, make and test it in
  this monorepo, then rebuild the submission.
- Keep build contexts within the submitted tree, retain dependency and image
  pins, and do not replace deterministic fixtures with private or live inputs.
