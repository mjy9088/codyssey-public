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

Keep generated observations in ignored artifacts or CI, not a checked-in run report. A
handoff names the exact checks performed, observed outcomes, unavailable checks and their
reason, and remaining risks. A passing mock does not establish deployment or live-service
behavior. An unavailable check is a limitation, never an implied pass.

## Review decision

Block approval for correctness or security defects, unclear ownership that duplicates an
invariant, broken isolation, undocumented compatibility changes, ineffective tests, or
claims unsupported by observed execution. Passing tests do not waive these findings.

Distinguish a concrete defect from a taste preference. A requested change should name its
failure mode or independent responsibility and the smallest coherent fix. Do not demand
gratuitous splitting of a sound module, or excuse a real defect as acceptable for coursework.

Source review and publication authorization are separate. This standard does not grant
permission to publish, deploy, access private material, or run supplied programs on the host.
