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
local commit and a course name, then creates a detached temporary worktree. It
materializes the development files from that revision's templates and tracked
course content, moves the resulting course tree to the repository root, and
creates one submission-layout commit. Revisions predating the templates export
the original course tree. The normal working tree is not reshaped.

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

`just submit B2-1` prepares from `HEAD` locally and never prompts or pushes. Use
`sh scripts/publish-coursework.sh --prepare --source REVISION B2-1` without Just
or to prepare a specific revision. Inspect the reported commit before transfer.
Without `--prepare`, the script asks for explicit confirmation on a terminal
before force-pushing; a noninteractive invocation does not push. A confirmed
run overwrites a diverged destination branch, so verify the approved destination
and branch before confirming.

Exercise the local preparation, validation, force-push confirmation, and cleanup
paths with synthetic repositories and a simulated push:

```sh
sh tests/publish-coursework-test.sh
```

The destination's tip contains the selected coursework and its materialized
tooling, but its parent commits retain the complete public monorepo history.
Use this method only when the public history reachable from the selected source
revision is acceptable at the destination.

The script intentionally creates the submission-layout commit in a disposable
worktree. Make fixes in the canonical coursework subtree, verify and commit them
on `public`, and then run the publication procedure again.

## History-free standalone archive

Use an archive instead when the destination must not receive any Git history.
Prepare locally and copy the reported **submission** commit ID (not the source
commit ID). Archive that commit's standalone tree:

```sh
sh scripts/publish-coursework.sh --prepare --source HEAD B2-1
git archive --format=tar --output=coursework-submission.tar PREPARED_COMMIT_ID
```

The archive contains the course files and generated development utilities, not
the parent history. Record the source revision outside the exported tree or in
destination metadata if traceability is required.

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
