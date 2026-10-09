# Conflict Resolution Procedure

The automated lab exercises two genuine Git conflict mechanisms in disposable repositories:

1. Two branches modify the same line. Resolve by retaining both independently useful lines, stage the
   result and create the merge commit.
2. One branch removes a file while another revises it. Resolve by retaining the reviewed revision.

Run `sh scripts/verify.sh docker` to exercise the mechanics and assertions. This is not a record of
two people resolving a GitHub conflict. For the actual team hand-in, add the real participants,
branches, conflicting intent, chosen resolution, PR/commit links, verification and prevention lessons.
This record is explicitly required for submission; otherwise a tracked execution log would be stale
and redundant with automation. Never replace real participation with synthetic fixture output.
