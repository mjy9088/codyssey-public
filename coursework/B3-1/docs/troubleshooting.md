# HTTP Routing Troubleshooting

This reproducible local case distinguishes a missing HTTP resource from a networking failure. It is
not an Azure incident report and does not claim a public deployment.

## Symptom and hypothesis

A request to `/not-present` returns HTTP 404 while `/health` returns HTTP 200 with `OK`. An HTTP status
means the request reached the service, so changing an NSG or route is not the appropriate first action
for this case.

## Reproduction and correction

`verify/check.sh` requests both paths against the selected Docker or QEMU server and checks the real
responses. Use the documented `/health` path. Both service paths execute the assertions rather than
substituting a stored response or static PASS record.

## Authorized Azure follow-up

For a real deployment, separate application routing from infrastructure reachability:

1. Confirm the Standard public IP is associated with the intended NIC and the VM is running.
2. Inspect effective routes; Azure combines system routes with the configured user-defined route.
3. Inspect effective NSG rules and verify TCP/80 is allowed while SSH is limited to the approved `/32`.
4. Check cloud-init and Nginx status inside the VM before changing network controls.
5. Request `/health` locally and externally, recording the actual status, body, and source client.

The QEMU result is not proof of Azure routing, NSG behavior, Ubuntu bootstrap, or public reachability.
A troubleshooting document is an explicit submission requirement; raw operational logs should normally
remain in reviewed CI or ignored artifacts because they become stale and can disclose infrastructure.
