# AI Git Review Drafts

This CLI reads `git status` plus staged and unstaged `git diff` output, then drafts a commit message
or pull-request description. The default fixture backend is deterministic, offline, and credential
free. It makes synthetic local verification safe and repeatable; it does not pretend to be a model.

## Run with Docker

Review the repository before exposing it to any container or model. From this directory, the bundled
synthetic repository demonstrates both commands:

```sh
docker compose run --rm reviewer commit
docker compose run --rm reviewer pr --model fixture-v1 --temperature 0.2 --max-tokens 600
```

To review another local repository with the offline backend:

```sh
docker build -t ai-git-review .
docker run --rm -v "$PWD:/repo:ro" -w /repo ai-git-review commit
```

The output is a draft only. The tool never commits, pushes, opens a PR, or changes repository files.

## Explicit API mode

Network use requires both the API backend and a separate opt-in flag. The API key is read only from
the environment and is never printed:

```sh
export OPENAI_API_KEY='replace-with-your-key'
docker run --rm -e OPENAI_API_KEY -v "$PWD:/repo:ro" -w /repo ai-git-review \
  pr --backend api --allow-network --model gpt-5-mini --temperature 0.2 --max-tokens 600
```

API mode sends one HTTPS request to the fixed OpenAI Responses endpoint, uses a 30-second timeout,
sets `store` to false, and validates the returned draft. Authentication, HTTP, timeout, malformed
response, and formatting errors are reported without exposing the key. Automated tests route the
adapter through an internal test-only opener to an ephemeral loopback HTTP service. This exercises
real request/response transport for success, authentication, rate-limit, server-error, malformed-JSON,
and missing-output cases while confirming the production request still targets the fixed HTTPS URL.
The loopback service is protocol simulation only: it uses synthetic credentials and responses and
does not prove model quality, model availability, TLS interoperability, or live service behavior.
Real API mode is intentionally not exercised because it would require credentials, incur cost, and
be nondeterministic. Confirm current model availability and pricing before opting in.

## Safety policy

Safe mode is on by default. It masks common `key`/`token`/`password`/`secret` assignments and email
addresses, sends at most 200 diff lines, and includes at most ten status entries/files. Repository
text is enclosed in prompt delimiters and explicitly treated as untrusted data. Binary content is not
expanded by Git's normal diff. These heuristics cannot identify every secret: inspect the diff first.
`--unsafe-include-sensitive` disables masking and bounds and should normally be avoided.

## Output examples

Commit drafts contain a one-line title (maximum 72 characters) and optional bullet body. PR drafts
contain a one-line title (maximum 80 characters) and bulleted `Why`, `What`, and `How to Test`
sections. For example, the offline demo describes `example.txt`, separates title/body with headers,
and ends with a reminder to review before applying.

## Verification

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

Docker mode runs 15 synthetic scenarios (nine offline/CLI checks and six loopback API-protocol checks)
plus the actual CLI. VM mode boots x86_64 Alpine under QEMU TCG and runs the same Python, Git, and
loopback protocol scenarios inside the guest. Each local server binds an ephemeral loopback port and
is stopped after its scenario. Neither mode requires KVM, privileged mode, a host Docker socket,
parent paths, cloud credentials, or external network access at runtime. Local verification does not
prove API availability, model quality, a GitHub push, a published repository, or a human-reviewed PR.

See [the review guide](docs/REVIEW.md) for expected boundaries and limitations.
