# Repository guidance

This public monorepo contains reference-quality implementations for the Codyssey
AI All-in-One course. Prefer idiomatic, maintainable best practices over solutions
that merely satisfy assessment checks.

- Apply `docs/QUALITY_STANDARDS.md` during implementation and review. Exercise completion
  and passing tests are a floor, not the approval target.
- Keep entry points, domain rules, I/O adapters, presentation, fixture administration,
  and composition independently owned. Do not split cohesive code just to add layers.
- Review actual user-facing behavior and affected callers; report unavailable checks
  honestly and resolve architecture/security blockers even when tests pass.
- Follow `docs/AGENT_WORKFLOW.md` for the pinned pstack skills. Use their architecture,
  test-first and adversarial-review methods, but never substitute model approval for
  execution evidence or let a playbook bypass publication/privacy restrictions.

- Write authored documentation in English.
- Keep restricted assignment text and supplied assets/data in the private workspace;
  use publishable synthetic fixtures for public tests.
- Keep each coursework project independently runnable with Docker Engine and Compose,
  without DIM, private materials, a host Docker socket, or real cloud credentials.
  Limit build contexts to the project directory.
- Keep `init.sh` as the sole root environment bootstrap entry point; its implementation
  and platform helpers belong under `environment/codyssey-init/`, not in root copies.
- Make fixtures and generation of logs, images, and other artifacts deterministic
  wherever practical. Retain the scripts needed to reproduce them.
- Prefer rerunnable verification over checked-in execution results. Keep run logs,
  reports, traces, and verification screenshots in ignored artifacts or CI storage
  unless an assignment explicitly requires them; document any such exception.
