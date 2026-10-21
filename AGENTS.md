# Repository guidance

This public monorepo contains reference-quality implementations for the Codyssey
AI All-in-One course. Prefer idiomatic, maintainable best practices over solutions
that merely satisfy assessment checks.

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
