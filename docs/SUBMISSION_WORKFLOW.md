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
standalone repository root and the public monorepo history. The script fetches
the latest `origin/public`, creates a detached temporary worktree, removes every
tracked path, moves the selected coursework subtree to the repository root, and
creates one submission-layout commit. It never applies those deletion or move
operations to the normal working tree.

First run it without publication enabled and review the commit summary:

```sh
scripts/publish-coursework.sh B6-1 \
  git@github.com:mjy9088/codyssey-submit.git
```

After confirming the selected subtree, destination, and target branch, repeat
the command with the explicit destructive option:

```sh
scripts/publish-coursework.sh --force-push B6-1 \
  git@github.com:mjy9088/codyssey-submit.git main
```

`--force-push` replaces the destination branch even when it has diverged. The
destination's previous branch tip may consequently become unreachable; confirm
that the repository and branch are dedicated to this submission before using
the option. The destination's tip contains only the selected coursework files,
but its parent commits retain the complete public monorepo history. Therefore
this method is suitable only when that public history is acceptable at the
destination.

The script intentionally creates the submission-layout commit in a disposable
worktree. Make fixes in the canonical coursework subtree, verify and commit them
on `public`, and then run the publication procedure again.

## History-free standalone archive

Use an archive instead when the destination must not receive any Git history:

```sh
revision=$(git rev-parse --verify HEAD)
subtree=coursework/B1-1
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
