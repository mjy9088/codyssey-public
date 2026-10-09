# HTTP Routing Troubleshooting

This candidate's reproducible local case distinguishes a missing HTTP resource from a networking
failure. It is not an AWS incident report and does not claim a real public deployment.

## Symptom and hypothesis

A request to `/not-present` returns HTTP 404 while `/health` returns HTTP 200 with `OK`. Because the
server returns an HTTP status, the request reached the HTTP service; changing a security group is
not the appropriate first action for this case.

## Reproduction and correction

`verify/check.sh` requests both paths against the selected Docker or QEMU server and checks the
responses. Use the documented `/health` path. The same assertions run through both real service
paths, rather than substituting a stored response or a static PASS record.

## Prevention and cloud follow-up

Keep a stable health route and verify status and body. During an authorized AWS deployment, separately
check DNS/address selection, routing, security-group source restrictions, listening ports, bootstrap
logs and application routing. Capture actual symptoms before changing settings. Do not copy this
local case as proof of AWS networking behavior.

A troubleshooting document is an explicit submission requirement. Normally execution narratives
should remain in reviewed CI/ignored artifacts because they become stale and may reveal operational
details; prefer the rerunnable check over committing raw logs.
