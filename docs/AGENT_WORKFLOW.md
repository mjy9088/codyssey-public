# Agent Architecture and Review Workflow

The repository uses selected [pstack](https://github.com/backnotprop/pstack) Agent Skills for
development judgment. They are not application dependencies, a code-analysis engine, or proof
that a change is correct. The implementation and verification rules in
[QUALITY_STANDARDS.md](QUALITY_STANDARDS.md) remain the approval contract.

## Install

```sh
sh scripts/setup-pstack.sh
```

This explicit developer command requires Git and Node.js 22 or newer. It downloads only the public
pstack repository, checks out pstack 0.15.32 at the full commit
`f51fdeba3d803ef90e4eaa4a95ffb4e76008ab37`, verifies `HEAD`, and then uses a reviewed Node.js
standard-library copier. It does not run npm, npx, Bun, package lifecycle scripts, or code from the
checkout.

The copier has authority to replace exactly 30 user-level skill directories: `architect`, `how`,
`why`, `arena`, `interrogate`, `tdd`, and the 24 reviewed `principle-*` skills named in
`scripts/lib/pstack.mjs`. It also replaces `~/.agents/skills/pstack.LICENSE` with the upstream MIT
license at mode `0644`. Other entries under `~/.agents/skills` are left unchanged. Before writing,
the copier reads every selected source file, requires exactly one matching frontmatter `name`, and
rejects nested skill declarations, symbolic links, or non-regular entries in the selected source
and owned destination trees. Complete copies are staged in a private temporary directory inside the
skills root; existing owned entries are backed up and restored if replacement fails.

The installer serializes replacement with `~/.agents/skills/.pstack-install.lock`. It removes the
lock after a successful install or a fully completed rollback. If rollback itself is incomplete, it
retains both the lock and the `.pstack-install-*` recovery directory so later runs cannot overwrite
the evidence needed for manual restoration. Inspect and restore that recovery data before removing
the lock; do not delete it merely to make a retry proceed.

Git runs with a temporary home, system and global configuration disabled, hooks and templates
disabled, credential helpers cleared, and interactive prompting disabled. The installer still needs
network access to public GitHub and invokes the host Git executable. Its filesystem checks cannot
defend against a malicious process running as the same user and concurrently changing paths between
checks and operations. The copied skills are passive Markdown and related data during installation,
but they can direct an agent to use tools when invoked later; this installer is not an operating-system
sandbox for subsequent agent activity.

Run the deterministic offline copier and CLI-boundary tests with:

```sh
node --test tests/pstack-installer.test.mjs
```

Restart OpenCode after installation because a running session does not hot-reload its skill catalog.
Re-run this reviewed script to restore the pinned set instead of enabling automatic updates against
an unreviewed branch.

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
   revision; do not turn cosmetic preferences into an endless rewrite. Require the module coverage
   and separate functionality/architecture verdicts in the quality standard, not just a defect list.
5. Independently run the project's checks and real-surface QA. A skill response or model consensus
   cannot replace those observations, and an intermediate commit is not final approval.

### Independent reviewer request contract

Every review request must supply the exact revision/worktree, the full scope and affected callers,
the applicable project constraints, and observed verification with its limitations. Direct the
reviewer to read the current complete implementation and apply
[the UI/policy distinction and mandatory coverage](QUALITY_STANDARDS.md#ui-mechanics-are-not-independent-policy).
Do not restrict architectural findings to already-observed runtime failures.

Require this response structure:

1. Revision, examined scope, and explicit omissions.
2. Module coverage: owned decisions, I/O/resources, state authority/projections, callers, execution
   evidence, and acceptance or concrete exception rationale.
3. Significant findings, including architectural defects that do not yet change visible behavior.
4. Separate functionality and architecture verdicts (`PASS`, `FAIL`, or `INCONCLUSIVE`), plus any
   security/correctness blockers. Missing required coverage is not a pass.

Keep revision-specific tables and observations in the response or ignored evidence, not tracked
review reports. Stable ownership documentation may describe intended responsibilities, but the
reviewer must verify them against code rather than repeat the author's table as proof.

Use only model routes and tools actually available in the harness. If the upstream skill requests
an unavailable model, document the substitute and do not claim cross-model diversity that was not
observed. This repository does not hardcode reviewer identities or provider credentials. Its
publication and operator-approval rules override any upstream playbook that proposes automatic
PR creation, merging, or deployment.
