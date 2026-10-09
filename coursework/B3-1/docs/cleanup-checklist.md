# Cleanup Procedure

This is a procedure, not a claim that a cloud run occurred. Record actual results only during an
authorized deployment; any required submitted cleanup record is an exception to the normal policy
of keeping run evidence out of Git.

- Delete the owned CloudFormation stack and wait for completion.
- Check the instance is terminated and its delete-on-termination root volume is gone.
- Remove only separately created, owned unattached volumes or allocated addresses.
- Verify gateway detach/delete, subnet, route table, security group and VPC cleanup.
- Check any optional NAT gateways, load balancers or databases created outside this template.
- Review billing and delayed usage records. A local emulator cannot validate absence of AWS charges.
