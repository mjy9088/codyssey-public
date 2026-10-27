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
