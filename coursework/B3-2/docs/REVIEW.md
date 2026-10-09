# Review guide

Run `sh scripts/verify.sh all`. Docker mode must report 15 passing scenarios, display an offline PR
draft, reject API mode without explicit network permission, and end with `DOCKER-VERIFY-SUCCESS`.
QEMU mode must identify the guest kernel, execute the same Python/Git scenarios inside that guest,
and end with both `VM-TEST-SUCCESS` and `VM-VERIFY-SUCCESS`.

Inspect these boundaries:

- Git commands use argument arrays, fixed subcommands, a 15-second timeout, and no shell.
- Default execution uses the offline fixture and reports zero API requests.
- API execution needs `--backend api`, `--allow-network`, and `OPENAI_API_KEY` together.
- Safe mode masks common sensitive patterns and bounds status, file, and line counts before prompting.
- Model text must use the exact title/body shape; title limits and every PR section/bullet are checked.
- The API endpoint is fixed HTTPS, request count is one, response storage is disabled, and errors are
  reduced to actionable status without printing request headers or credentials.
- Six API-adapter scenarios use ephemeral loopback HTTP servers to simulate success, authentication,
  rate-limit, server-error, malformed-JSON, and missing-output responses. They verify protocol handling,
  not TLS, live API availability, or model quality; no production endpoint override is exposed.

The formatter cannot determine whether generated prose is factually correct or whether a masked diff
contains an unrecognized secret. Human inspection remains mandatory. Fixture output verifies the
automation and validation pipeline, not AI quality or live service behavior.

Execution logs and generated drafts are not tracked because they become stale, duplicate rerunnable
automation, and can disclose repository content. Keep local evidence in ignored artifacts or CI.
