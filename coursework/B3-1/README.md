# Isolated Network Candidate

This subtree combines a reviewable AWS topology with a repeatable local API/service laboratory.
The conceptual topology is in [architecture.png](docs/architecture.png), generated from its SVG
source by `sh scripts/render-diagram.sh`; it is a design diagram, not an execution capture.
It is not evidence that anything was deployed to AWS. Real cloud deployment, SSH from an approved
address, an external URL/capture, effective IAM authorization, and billing cleanup require a separately
authorized account and remain external submission conditions.

## Local checks

Run `sh scripts/verify.sh all` with Docker Engine and Compose. `docker` uses an unprivileged Nginx
server; `vm` serves the same files from a real QEMU TCG Linux guest. Both create and inspect a VPC,
subnet, gateway, route table and narrowly scoped security-group metadata in LocalStack, then remove
them. They also pass the actual `infrastructure/template.json` through CloudFormation validation,
create it with a mock EC2 record, inspect stack outputs and backed EC2 metadata, reject malformed
JSON and duplicate stack names, execute an SSH-source change set, delete it, recreate it, and clean
it up. Runtime networking is internal. First image/package downloads need network access.

LocalStack models these APIs but does not enforce AWS security-group or IAM data-plane semantics.
In pinned Community 4.11.1, CloudFormation accepts a `SshSource` value that violates the template's
`AllowedPattern`, marks the default route complete without exposing that route through EC2 metadata,
and omits inline security-group ingress metadata. Its mock instance reports `HttpTokens=optional`
and `Encrypted=False` despite the template requirements. Deterministic template regressions and
direct EC2 API checks cover those contracts instead; they do not prove enforcement, IMDSv2, or EBS
encryption. The VM proves a separate kernel and HTTP service, not an EC2 instance. Do not confuse
these layers. No host socket, KVM, privileged container, cloud token, or parent directory is needed.

## Reviewed deployment inputs

`infrastructure/template.json` defines one public subnet and one small web instance. It intentionally
requires an explicit AMI and existing key pair; no moving AMI alias or real credential is stored.
`infrastructure/deployer-policy.json` is a service/action/region-limited review starting point, not
a claim of account-specific least privilege. Mutations use ownership/request-tag conditions;
account-specific ARNs and each API's condition support must be reviewed before real use. It deliberately
does not grant IAM administration, PassRole, S3, RDS, or other unrelated services.
Use only `ap-northeast-2`, a non-root principal, an approved account policy, and a trusted `/32` SSH
source. The instance requires IMDSv2 and an encrypted root volume deleted at termination. Review
Ubuntu package updates during an actual deployment; the local server uses a pinned image instead.

Do not run a real deployment automatically from this workspace. After authorization, validate the
template, review a change set, deploy with the explicit parameters, test `/health` both inside the
instance and from outside, and delete the stack. Examine retained volumes and addresses and the
billing console rather than assuming stack deletion proves absence of costs.

Read `docs/REVIEW.md` for the boundary between local checks and real-cloud assessment. Required
cloud screenshots/reports must be produced from an actual authorized run, not invented. They are
submission exceptions: normally keep run outputs in CI artifacts or ignored `artifacts/`.
