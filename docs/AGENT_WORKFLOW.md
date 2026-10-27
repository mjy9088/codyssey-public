# Agent Architecture and Review Workflow

The repository uses selected [pstack](https://github.com/backnotprop/pstack) Agent Skills for
development judgment. They are not application dependencies, a code-analysis engine, or proof
that a change is correct. The implementation and verification rules in
[QUALITY_STANDARDS.md](QUALITY_STANDARDS.md) remain the approval contract.

## Install

```sh
sh scripts/setup-pstack.sh
```

This explicit developer command uses Git, Node.js, and npm. It installs user-level OpenCode skills
from pstack 0.15.32, commit `f51fdeba3d803ef90e4eaa4a95ffb4e76008ab37`, through the pinned
`skills@1.7.4` installer. It copies `architect`, `how`, `why`, `arena`, `interrogate`, `tdd`, and the
principle skills, retaining the upstream MIT license. It does not change application manifests,
install frontend runtime code, configure model accounts, or publish anything. Existing skills
with these selected names are replaced by the pinned copies; other skills are not selected.

The installer needs network access to public GitHub/npm sources. It does not upload repository
contents. Restart OpenCode after installation; a running session does not hot-reload its skill
catalog. Re-run this reviewed script to restore the pinned set instead of enabling automatic
updates against an unreviewed branch.

## Use the skills, then prove the result

1. Use `how` to explain the real callers, owned decisions, side effects, and dependency direction.
   Use `why` only with available, authorized context. Private coursework must never be sent to a
   public search, issue, or external service as context.
2. Use `architect`/`arena` when a nontrivial interface or ownership decision needs alternatives.
   Compare structurally different shapes on invariants, caller complexity, and module depth.
   Reject pass-through layers and duplicated ownership rather than rewarding more files.
3. Use `tdd` for a defect or new boundary: observe the relevant failure, implement, and exercise
   the actual artifact. Checkpoint coherent working changes while the broader review is open.
4. Use `interrogate` for adversarial review of the current implementation and all affected callers.
   Apply its rubric and code-quality lens. Resolve significant findings and re-review the new
   revision; do not turn cosmetic preferences into an endless rewrite.
5. Independently run the project's checks and real-surface QA. A skill response or model consensus
   cannot replace those observations, and an intermediate commit is not final approval.

Use only model routes and tools actually available in the harness. If the upstream skill requests
an unavailable model, document the substitute and do not claim cross-model diversity that was not
observed. This repository does not hardcode reviewer identities or provider credentials. Its
publication and operator-approval rules override any upstream playbook that proposes automatic
PR creation, merging, or deployment.
