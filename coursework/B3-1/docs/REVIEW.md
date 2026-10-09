# Network Review Guide

- Inspect subnet/gateway/default-route links in the template, not just resource names.
- Confirm HTTP is public while SSH has one deliberate source address. No all-port ingress exists.
- Use a non-root AWS identity restricted to necessary EC2 networking/instance actions and the named
  CloudFormation stack; broad account administration, unrelated services, and wildcard admin policies
  are not acceptable. An actual account policy must be reviewed before deployment.
- Run Docker and VM local verification and inspect failures without treating emulator responses as
  AWS authorization evidence.
- Inspect the LocalStack CloudFormation create/change-set/update/delete/recreate results. Community
  mock mode verifies the template lifecycle and several control-plane records, but its observed gaps
  for parameter-pattern enforcement, route reflection, inline ingress, IMDSv2, and EBS encryption
  are covered by static contracts or direct EC2 API tests rather than represented as cloud proof.
- Confirm the AMI is the intended Ubuntu amd64 image in the deployment region and record the actual
  input through the reviewed deployment configuration, not a duplicate source-checksum inventory.
- During a real run, confirm SSH, package/bootstrap completion, HTTP, expected health body, outbound
  access and the restricted source rule from appropriate clients.
- The public URL and required external capture are intentionally not fabricated here.

Cloud run evidence is an explicit submission exception. It becomes stale and may expose addresses
or identity metadata, so keep raw logs ignored and review the minimum required evidence before
including it. The reproducible local checks are preferred over static PASS reports.
