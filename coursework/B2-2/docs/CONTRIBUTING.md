# Contribution Workflow

Use GitHub Flow: keep the shared main branch releasable, use short-lived feature branches, and review
before merge. This keeps integration visible without requiring a complicated release hierarchy.

- Name branches `feature/<person-or-team>/<purpose>` in the separately approved team repository.
- Use meaningful `feat:`, `fix:`, `test:`, or `docs:` subjects describing the affected behavior.
- Open an issue before implementation and connect the PR with a real `Closes #number` reference.
- Explain what changed, why, and how another person can verify it. Attach links to genuine evidence.
- Require at least one independent approval and successful checks before merge; prohibit direct main
  pushes through GitHub branch protection, not just a written convention.
- Review concrete lines, behavior, failure modes and alternatives. An approval-only slogan is not a
  substantive review. The author should answer and apply or explain each requested change.
- Coordinate conflicting changes before resolving them; preserve intended behavior and rerun tests.
- Never force-push a shared branch or impersonate a contributor. Local fixture identities are test data.
