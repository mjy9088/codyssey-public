# Codyssey AI All-in-One

This repository is the public working monorepo for the Codyssey AI All-in-One
course. It contains material that is safe and useful to publish: source code,
reproducible development environments, engineering notes, tests, and explicitly
required sanitized deliverables.

## Environment bootstrap

Review the [environment documentation](environment/codyssey-init/README.md), then
start the bootstrap from a trusted network with:

```sh
curl -fsSL https://raw.githubusercontent.com/mjy9088/codyssey-public/main/init.sh | sh
```

The new short URL becomes available after the root entry point is published to
GitHub. Before then, run `sh init.sh` from this local repository root.

The short URL streams a mutable `main` wrapper and, by default, buffers the Bash
environment bootstrap from the same mutable branch before running it. Both must
therefore be trusted at execution time. Use a reviewed local checkout when a fixed bootstrap revision is needed.

## Repository map

| Path | Purpose |
| --- | --- |
| `init.sh` | Short POSIX entry point for the environment bootstrap |
| `environment/codyssey-init/` | Classroom and local development-environment bootstrap |
| `coursework/` | Current, self-contained coursework projects |
| `archive/E1-1/` | Imported E1-1 work, with its original Git history |
| `archive/E1-2/` | Imported E1-2 work, with its original Git history |
| `archive/E1-3/` | Imported E1-3 work, with its original Git history |
| `docs/` | Repository policy and submission workflow |

Additional course work should normally be added under a clearly named course or
project directory rather than at the repository root.

Current coursework:

- [`B1-1`](coursework/B1-1/) and [`B1-2`](coursework/B1-2/)
- [`B2-1`](coursework/B2-1/) and [`B2-2`](coursework/B2-2/)
- [`B3-1`](coursework/B3-1/) and [`B3-2`](coursework/B3-2/)
- [`B4-1`](coursework/B4-1/) and [`B4-2`](coursework/B4-2/)
- [`B5-1`](coursework/B5-1/) and [`B5-2`](coursework/B5-2/)
- [`B6-1`](coursework/B6-1/), [`B6-2`](coursework/B6-2/), and
  [`B6-3`](coursework/B6-3/)

## Repository roles

- **This repository (`codyssey-public`)** is the canonical public workspace and
  monorepo.
- **The private workspace** is the canonical home for assignment text, restricted
  course material, credentials, personal data, and anything whose publication
  rights are unclear.

Read [the repository policy](docs/REPOSITORY_POLICY.md) before adding content.
When an assessment requires a different tree layout, use the optional
[submission workflow](docs/SUBMISSION_WORKFLOW.md).

## Imported history

Projects under `archive/` retain imported histories joined into this repository.
Git is the provenance record; inspect the reachable lineages directly instead of
maintaining a duplicate commit inventory:

```bash
git log --graph --oneline --decorate --all
```

## Working here

Keep changes scoped to one project when practical, run the checks documented in
that project's README, and never copy restricted assignment content into an
issue, commit, test fixture, screenshot, or generated artifact. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the normal workflow.

## Verification entry points

Run coursework checks from the selected project directory, not the monorepo root:

```sh
cd coursework/B2-1
sh scripts/verify.sh docker
```

All current projects under `coursework/` provide `scripts/verify.sh docker` and
`scripts/verify.sh vm`. The latter boots a separate Linux guest under QEMU TCG;
it is slower and is not a cloud deployment check. Read each project's README for
download, memory, network, and simulation boundaries. Docker Engine, Compose, and
a POSIX shell are the common host prerequisites. Do not run checks against real
credentials or replace the synthetic fixtures with restricted inputs.

Other entry points have different scopes:

| Location | Command from that location | Scope |
| --- | --- | --- |
| Repository root | `sh scripts/check-init.sh` | Isolated tests of the root bootstrap wrapper, not a host installation |
| `archive/E1-2/` | `sh scripts/verify.sh docker` | Containerized quiz application tests |
| `archive/E1-3/` | `just check` | Local Python checks using the archive's declared tools |
| `archive/E1-1/` | `bash lab.bash up`, `bash lab.bash run`, `bash lab.bash down` | Legacy privileged Docker-in-Docker lab; review its Compose mounts before use |

There is deliberately no command that installs or runs every environment at once.
Workflows inside archived or coursework `.github/` directories are not discovered
by GitHub Actions while nested in this monorepo. Historical workflow links do not
establish that the current checkout passes; rerun the relevant entry point.
