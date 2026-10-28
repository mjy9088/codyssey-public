# Implementation and Review Standard

## Target

Coursework implementations in this repository are maintainable reference implementations,
not minimum-score submissions. Meeting an exercise checklist and passing its current tests
are necessary, but neither is sufficient for approval. Apply the same engineering review
to application code, shell tools, infrastructure, fixtures, and verification code.

Preserve each project's documented learning constraints. A handwritten data structure must
not be replaced with a library, and an intentionally small program does not need an
enterprise framework. Quality means clear ownership and correct behavior, not more layers.

## Responsibility and dependency boundaries

- Entry points parse arguments, compose dependencies, invoke an application operation, and
  translate its result into an exit status or response. They do not own persistence or
  business rules.
- Domain code owns state transitions and invariants. Keep HTTP requests, filesystem formats,
  templates, process execution, and framework request objects outside that boundary.
- Adapters own external formats and resource lifetimes. Parse untrusted data once at the
  boundary, pass meaningful values inward, and translate expected failures at the caller's
  boundary. Do not conceal programming errors with broad catches or silent fallback success.
- Presentation owns markup, formatting, and interaction state. Services must not construct
  HTTP responses; UI components must not embed backend administration or fixture datasets.
- Composition owns connection setup and dependency wiring. Keep deterministic seed data and
  demo administration separate from ordinary CRUD and schema initialization.
- Give each invariant one mutation path. Deletion, eviction, expiry, and overwrite must not
  maintain independent copies of the same accounting or cleanup rules.
- Keep modules cohesive, not merely short. Review files above 250 nonblank, noncomment lines
  for decomposition before extending them. An indivisible algorithm or declarative dataset
  needs a concrete explanation, not line compression or an unexplained exemption.
- Do not create a forwarding class, generic framework, or interface solely to move lines.
  Keep a small aggregate together when its operations share one invariant. Extract when
  responsibilities change for different reasons or resource ownership becomes unclear.
- Standalone coursework must not import sibling projects or root implementation helpers.
  Small local policy helpers may be intentionally repeated to preserve that isolation.

### Prove the boundary, not the filename

Before approving a structural change, identify each module's owned decisions and
side effects, then trace the actual imports and affected callers. A directory name,
short file, interface, or diagram is not evidence that the dependency direction is
correct. Check whether changing an external format, validation rule, or rendered
component would require editing an unrelated layer.

- Validation, selection, normalization, and state rules must be executable with plain
  values outside the UI runtime. Exercise them without a browser DOM, framework
  request, database connection, or hidden global initialization. Adapters may obtain
  inputs and present results, but may not be the only home of those rules.
- Define what a stylesheet layer means. A neutral reset must not depend on project
  theme tokens or feature classes. Themed document foundations may consume tokens;
  component appearance and page composition need explicit owners. Do not impose a
  universal ban on token use in every file called `base`; inspect its declared role.
- Trace combined CSS states through the cascade. When motion and a component share
  an element, verify ownership of transforms, transitions, animations, and reduced
  motion in the computed browser result, not merely their source declarations.
- Keep authored source normally formatted. Compressed multi-operation lines do not
  make a large responsibility small. Use automated formatting and static checking
  where available; a line-count gate must never reward minification.
- Explain legitimate exceptions with the current contract and concrete tradeoff.
  Do not accept a forwarding layer that leaves the original dependency unchanged.

### UI mechanics are not independent policy

Classify owned decisions, not all code containing an `if`, and not all uses of a browser API.
Presentation may own focus, menu visibility, touched/error display flags, pending controls,
observer enrollment, viewport breakpoints, and rendering-specific motion. These decisions describe
the interface itself. A cohesive view controller may coordinate those mechanics without a separate
store, reducer, service, or file for each operation.

Independent policy includes validation, acceptance/selection, ordering, preference precedence,
fallback choice, and state invariants that remain meaningful when the view or I/O implementation
changes. Such rules must accept ordinary values and execute without DOM/framework initialization
or external I/O. For example, whether an explicit theme choice overrides the system preference is
policy; updating the theme button's ARIA state is presentation. Storage access and media preference
observation are environmental inputs, not the authority that decides that precedence.

Identify each state's authority and its projections. An input's value or a menu's accessibility
state may be native UI state. Do not use rendered attributes, classes, labels, or computed styles as
the authority for an independent policy. Computed style may still supply presentation values, such
as the resolved canvas color projected into browser theme metadata.

Keep external formats, persistence, and environmental input acquisition at explicit adapter
boundaries. UI-specific browser mechanics such as intersection observation and responsive layout
measurement may remain in their view controller when they serve only that rendering lifecycle.
Classify the decision and its change axis; the API name alone does not settle ownership.

An architectural defect need not already cause a visible malfunction. Show the independently
changing decision, misplaced dependency/state authority, duplicated invariant, or inability to
execute a rule independently. Green browser tests prove behavior, not this separation. Conversely,
an extraction request must identify that responsibility: moving a comparison to a forwarding helper
or imposing a fixed layer/file count is not an improvement.

An exception must name the responsibility being kept together, its shared invariant or rendering
lifecycle, the concrete tradeoff, and the evidence that the retained boundary is sound. "Small",
"one feature", "the tests pass", or "a previous reviewer approved it" is not sufficient alone.

### Mandatory architecture-review coverage

Every independent architecture review must identify its revision and scope, including unchanged
modules and affected callers within that scope. In its response or ignored evidence, include a
coverage table with these columns:

| Module or explicitly named cohesive group | Owned policy / UI mechanics | I/O and resources | State authority / projections | Callers and proof | Architecture verdict / exception rationale |
|---|---|---|---|---|---|

Use `none` where a category does not apply; do not silently omit it. Group files only when their
ownership is genuinely identical, and name every member. Trace both the import graph and the actual
decisions inside allowed modules. An import rule cannot detect a policy copied into a UI function.
For each independent rule, identify its plain-value execution evidence; for retained UI mechanics,
explain why browser/framework execution is the appropriate proof.

Report functionality and architecture separately as `PASS`, `FAIL`, or `INCONCLUSIVE`. Functional
success must not imply architectural approval. A required module, caller, or evidence category not
examined makes the corresponding verdict inconclusive; it cannot be counted as a pass. State all
omissions explicitly. Overall approval requires both verdicts to pass and all significant security
or correctness findings to be resolved.

This is review coverage of the current implementation, not a prescribed module inventory or a
checked-in run report. Keep stable ownership contracts in architecture documentation, but put
revision-specific coverage, observations, and reviewer decisions in the response or ignored evidence.
Do not add prose-matching tests for these instructions; use dependency checks and executable rule
and surface tests as complementary evidence.

## Behavioral preservation

Before a structural change, identify callers and run the existing relevant tests. Preserve
shipped CLI commands, output formats, HTTP routes and status codes, validation, persistence
formats, authentication, transaction boundaries, and cleanup guarantees. Update all callers
when an internal module moves; do not leave accidental re-export layers behind.

Use existing tests to characterize refactors. Add focused regression coverage when fixing
an uncovered behavioral boundary. Assert observable outcomes, not only module names or
source fragments. Architecture checks may enforce forbidden dependencies, but must not
substitute for executing the application. Do not remove, skip, loosen, or regenerate an
expectation merely to turn a failure green. Intentional visual updates require inspection
before refreshing baselines and a normal comparison run afterward.

Tests must permit an internal refactor that preserves behavior. Do not freeze an
exact module inventory or selector spelling as a substitute for an architectural
rule. Replace such a pin with a dependency-boundary check and an equal or stronger
behavioral test. Preserve actual public asset paths, formats, and runtime constraints.

## Verification required for approval

1. Inspect the complete change and all affected callers, including packaging and deployment
   inputs. Review new files as well as the tracked diff.
2. Run relevant syntax/type/lint checks and targeted behavior tests. Run the documented
   container verification for affected projects and guest verification when guest code or
   packaging changes. Do not silently substitute host execution for an isolated lab.
3. Use the deliverable through its real surface: a CLI session, a browser interaction, live
   HTTP calls, or a module driver. Include a normal operation and a relevant failure path.
4. For UI changes, inspect responsive, keyboard, error, loading, and theme states rather
   than relying on screenshots or automated accessibility checks alone.
5. Confirm resource cleanup, repeat-run behavior, deterministic fixtures, and independently
   runnable build contexts. Check failed and interrupted runs where lifecycle code changes.
6. Obtain independent review of correctness, architecture, security, and the rendered
   interface when applicable. Authors must resolve blocking findings before approval.

The independent reviewer must read the current complete implementation, not just
the diff, the author's summary, or a previous passing review. Ask it to challenge
the chosen boundaries and test effectiveness. Require each significant finding to
name the failure mode, affected responsibility or caller, and evidence. Cosmetic
preferences alone do not keep a review open. Fix meaningful findings and review
the current revision again; an earlier approval is not transferable evidence.

Keep generated observations in ignored artifacts or CI, not a checked-in run report. A
handoff names the exact checks performed, observed outcomes, unavailable checks and their
reason, and remaining risks. A passing mock does not establish deployment or live-service
behavior. An unavailable check is a limitation, never an implied pass.

## Progress and completion

Use distinct statements for implemented, automatically verified, manually exercised,
and independently reviewed. A commit records progress, not approval. Commit coherent,
runnable checkpoints after their relevant checks, even while the broader review is
still open; do not wait for a perfect final revision to preserve working progress.
State the remaining review scope instead of calling that checkpoint complete.

Do not mark the requested work complete while a significant known architectural or
behavioral defect remains in scope. A passing suite, clean type check, previous
approval, or small diff does not waive it. An unresolved environment limitation
must be named with the capability it prevents verifying, not hidden by a fallback.

## Review decision

Block approval for correctness or security defects, unclear ownership that duplicates an
invariant, broken isolation, undocumented compatibility changes, ineffective tests, or
claims unsupported by observed execution. Passing tests do not waive these findings.

Distinguish a concrete defect from a taste preference. A requested change should name its
failure mode or independent responsibility and the smallest coherent fix. Do not demand
gratuitous splitting of a sound module, or excuse a real defect as acceptable for coursework.

Source review and publication authorization are separate. This standard does not grant
permission to publish, deploy, access private material, or run supplied programs on the host.
