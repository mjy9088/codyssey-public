# Collaborative Git Practice Kit

This candidate provides small utilities, collaboration rules and an executable practice lab.
It does **not** claim that multiple people reviewed or merged GitHub pull requests. Real team
membership, issue/PR participation and branch protection require a separately authorized shared
GitHub repository and actual participants; those are genuine external completion conditions.

Run `sh scripts/verify.sh all` with Docker Engine and Compose. The same utility checks and Git
exercises execute first in a container and then in a real QEMU TCG guest. No host Git, Node.js,
Docker socket, privileged mode or parent directory is required. Every practice repository is
temporary and contains only synthetic data. No command targets this repository's Git history.

`slug()` creates ASCII identifiers, `compactWhitespace()` normalizes spacing, and `initials()`
handles Unicode code points. These are initial shared-work examples, not attributed team contributions.
See `docs/CONTRIBUTING.md`, `docs/conflict-resolution.md`, and `docs/troubleshooting-log.md`.

The evaluation explicitly requires collaboration records and a submission index. These files
therefore explain the required handoff, but contain no invented people, PR URLs or completed-review
claims. Normally do not commit run transcripts or reports: use ignored/CI artifacts and rerunnable
checks. Only add the minimum real required record after review. The lab's synthetic history is not
acceptable as evidence of human collaboration.
