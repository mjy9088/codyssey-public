# Coursework development

From the monorepo root, materialize the tools for one course, then install its
pinned runtimes and locked project dependencies:

```sh
sh scripts/coursework.sh materialize B2-1  # or: just materialize B2-1
cd coursework/B2-1
mise trust
mise run setup
mise exec -- just                          # discover recipes
mise exec -- just demo
mise exec -- just check
```

If mise shell activation is enabled, use `just` directly. In a standalone
submission these files are already present: start with `mise trust` from the
submission root. Trust only configuration from a revision you have reviewed.

`demo` runs an interactive app or a synthetic feature scenario. `check` runs
on the host without a Docker daemon or QEMU. It checks the same application
where feasible but does not replace the separate `verify-docker` or `verify-vm`
recipes, which exercise the existing isolated workflows. No host verifier
starts an assessment-supplied input, live Azure resource, or real API call.

## Host requirements

- Git, POSIX shell tools, and mise. Package setup downloads the pinned toolchain
  and locked dependencies from the public registries. B3-1 also initializes
  both AzureRM roots with `-backend=false` and read-only dependency locks.
- B1-1, B1-2, B6-2, B6-3: Chromium is installed by `mise run setup`. The host
  needs Playwright's platform libraries and fonts. On Debian/Ubuntu, run
  `mise exec -- just _browser-deps` if these libraries are absent. The B1-1
  image comparisons retain their existing baselines; use pinned Docker/VM
  verification for the reference font and rendering environment.
- B4-1 and B4-2: Linux with `/proc` and the native kernel utilities used by each
  lab. B4-1 needs Bash, GNU awk and coreutils, iproute2 (`ss`), procps, and
  netcat-openbsd; B4-2 needs procps and a C11 compiler with pthread headers. The
  dev image includes these. Use isolated verification if existing processes,
  the firewall, or open ports would affect the lab.
- B6-1's mise-pinned SQLite binary uses conda-forge and requires glibc on Linux.
  Use the Docker shell on musl-based hosts such as Alpine.
- E1-1: Bash and GNU coreutils (including `stat`) for the native demo and
  checks. The full lab additionally needs a Docker host that supports privileged
  Docker-in-Docker and local bind mounts, and Compose v2.24.4 or newer. The
  development shell is unprivileged and only runs the native workflows.

## Docker development shell (no host mise or just)

```sh
sh scripts/coursework.sh shell B2-1
sh scripts/coursework.sh shell B2-1 -- just demo
sh scripts/coursework.sh shell B6-3 --web -- just demo
```

From a standalone submission, replace `sh scripts/coursework.sh shell COURSE`
with `sh .coursework-dev/shell.sh`. The launcher builds a project-scoped snapshot
with the toolchain and dependencies installed inside the Linux image. Container
changes are disposable. Rebuild after editing; there is no bind mount, host
Docker socket, or automatic credential forwarding. `--web` publishes port
8000 only on the Docker daemon host's loopback. The existing Docker/VM recipes
are run from the host, not from inside this shell.

| Course | `just demo` | Additional entry point |
| --- | --- | --- |
| B1-1 | Portfolio and contact UI on port 8000 | `just check` runs the browser suite |
| B1-2 | Production build with real local Firebase emulators and browser scenarios | `just preview` and `just stop-preview` for an interactive Compose preview on port 8088 |
| B2-1 | Ledger add/search, budgets, update/delete and CSV round trip | `just ledger --help` for the interactive CLI |
| B2-2 | Synthetic Git conflicts, amend, reset, revert and stash | `just check` also checks the documented collaboration boundaries |
| B3-1 | Static health page on port 8000 | `just check` runs mock-provider Terraform tests; `just diagram` uses Docker |
| B3-2 | Commit and PR drafts from a disposable synthetic repository | `just check` covers local draft and safe transport behavior |
| B4-1 | Monitoring, report parsing, warnings and rotation on Linux | `just verify-vm` for isolated Linux verification |
| B4-2 | Bounded memory, CPU and thread scenarios on Linux | `just verify-vm` for isolated Linux verification |
| B5-1 | Key lookup, expiry and LRU eviction | `just repl` |
| B5-2 | Branch/merge, ordering, search and graph traversal | `just repl` |
| B6-1 | All 17 SQLite queries against a disposable database | `just check` compares the golden output |
| B6-2 | Catalog CRUD on port 8000 | `just browser` verifies CRUD using a fresh SQLite database |
| B6-3 | Authentication, catalog, lending and returns on port 8000 | `just browser` verifies browser flows using a fresh SQLite database |
| E1-1 | File operations and permission changes in a temporary directory | `just verify-docker` runs the full DinD workstation lab |
| E1-2 | Add, list and play a quiz, then reload its score in a temporary directory | `just run` for interactive play, `just verify-docker` for isolated tests |
| E1-3 | 3×3 MAC classification in manual mode | `just analyze` processes the bundled JSON, `just verify-docker` runs isolated tests |

B1-2 `check` also runs the owner-isolation probe. The checked-in shared-demo
policy permits cross-user access, so the probe reports that limitation as a
nonzero result. `demo` runs the feature flow but does not claim owner isolation.

## Editing workflow files

Edit the shared templates in `coursework-tools/`, course-specific recipes in
`coursework/COURSE/workflow.just`, and runtime pins in `scripts/coursework.sh`.
Rerun materialization after changing templates or staging new course files for
the dev image. Docker uses an allowlist derived from that course's Git index
plus the generated inputs, with sensitive-path exclusions applied last. Do not
stage credentials or private inputs, even temporarily. Generated files are
ignored in the monorepo and included as regular files in a standalone export.
See [Submission workflow](SUBMISSION_WORKFLOW.md) for preparation and transfer.
