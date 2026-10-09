# Submission Workflow

## Principle

Develop and review work in this monorepo. Submit the canonical coursework subtree
unchanged when the approved destination accepts it. A standalone export is an
optional transport artifact only when the required hand-in layout differs; it is
not another development source of truth.

## Prepare a hand-in

1. Read the selected project's README and applicable `AGENTS.md`.
2. Verify the exact public revision with the project's documented checks.
3. Inspect the selected subtree for secrets, restricted material, generated run
   artifacts, and files outside the assessment scope.
4. Submit that subtree directly if its layout is accepted.
5. Only when a standalone root is required, export the subtree to a temporary
   directory and apply the minimum required layout-only changes there.
6. Re-run the relevant checks against the exported tree when its layout changed.
7. Transfer the result only to the explicitly approved destination. A local
   export does not demonstrate a push, publication, or deployment.

## Optional standalone export

Use Git to select an exact revision without copying unrelated monorepo paths:

```sh
revision=$(git rev-parse --verify HEAD)
subtree=coursework/B1-1
staging=$(mktemp -d)
git archive "$revision" -- "$subtree" \
  | tar -x -C "$staging" --strip-components=2
```

Replace the example subtree with the project being submitted. Record the source
revision outside the exported tree or in destination metadata if traceability is
required; do not add a repository status or provenance inventory. The export has
no Git history by default. If the destination requires history, use its approved
procedure rather than inventing branch, commit-count, or retention rules.

## Guardrails

- Never copy content from the private workspace into a public submission unless
  it has first been deliberately sanitized and made canonical here.
- Never include credentials, private URLs, restricted assignment text, supplied
  data, or private evidence in an export.
- Do not merge submission-only deletions or renames back into this monorepo.
- If a fix is discovered during preparation, make and test it in
  this monorepo, then rebuild the export.
- Keep build contexts within the exported subtree, retain dependency and image
  pins, and do not replace deterministic fixtures with private or live inputs.
