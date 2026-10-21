# Azure Network Candidate

This standalone subtree describes a small Azure web VM and verifies its Terraform configuration
without cloud credentials. The conceptual topology is in [architecture.png](docs/architecture.png),
generated from its SVG source by `sh scripts/render-diagram.sh`; it is a design diagram, not an
execution capture. Nothing here is evidence that Azure resources were created, that an NSG or RBAC
assignment was enforced, or that a public endpoint was reached.

## Reproducible local checks

Run from this directory with Docker Engine and Compose:

```sh
sh scripts/verify.sh --help
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

`docker` checks the site in an unprivileged Nginx container. `vm` boots an x86_64 Alpine guest under
QEMU TCG and checks the same site through guest networking. Both compare the complete `/` and
`/health` response bodies with the repository files and require `/not-present` to return 404; VM mode
also checks its generated kernel proof endpoint. Runtime networking is an internal Compose network
with no external egress.

The verifier uses Terraform's explicitly named `mock_provider "azurerm"`, not an Azure emulator.
It runs positive topology, exact cloud-init payload, output, and resource-group-scoped RBAC tests
plus negative tests for open/malformed SSH sources, malformed public keys, moving image aliases, and
invalid principal IDs. Mocks exercise the real provider schema without credentials or API calls.
They do not implement the Azure control plane or dataplane.

During the verifier image build, pinned Alpine `cloud-init` `24.3.1-r2` validates the cloud-config
schema and renders its `runcmd` through the real `cc_runcmd` module. The rendered commands then run
inside that disposable build stage. The shell writes are real and their complete health output and
key index content are checked; package installation and service management use recording stubs whose
exact arguments are checked, so the build has no package or service side effects. This proves local
schema, rendering, command syntax, ordering, and file effects. It does not reproduce Ubuntu boot,
APT installation, systemd, or Azure provisioning. Image construction downloads pinned tools and
packages; the Compose verification runtime remains offline.

The verifier image pins Terraform `1.16.5` and selects its Linux archive from the build host
architecture: `amd64` SHA-256
`2bc2fcfff033265c9e02ca0351f01794eb122f62a9b2a49a3294b9e49eaab5e4`, or `arm64` SHA-256
`61a50b00485ee4810cf20581ef080fc54d34d666e175c58d9a10501c65c1ccde`. It mirrors the matching
AzureRM provider platform. Both Terraform roots pin AzureRM `4.66.0`, and their locks contain the
official ZIP hashes for every published platform. Building the verifier downloads the selected
Terraform archive and provider; runtime initialization is offline, uses `-lockfile=readonly`, and
uses only the installed filesystem mirror. Local verification records only the architecture of the
host on which it actually ran; source support for another architecture is not evidence of a test there.

## Terraform roots and responsibility split

| Path | Operator | Purpose |
| --- | --- | --- |
| `infrastructure/access-bootstrap/` | Authorized Azure role manager | Create the dedicated resource group, custom deployer role, and one assignment |
| `infrastructure/deployment/` | Restricted lab deployer | Look up that resource group and manage only the reviewed network, VM, and disk graph |

The deployer configuration cannot create a resource group, custom role, or role assignment. Its
custom role is assignable only at the lab resource group and contains no
`Microsoft.Authorization/*`, wildcard, or data action. The role manager still needs pre-existing
permission to create the resource group, role definition, and role assignment. Before either root is
used, an authorized subscription operator must preregister `Microsoft.Network` and
`Microsoft.Compute`; both AzureRM provider blocks disable automatic registration and the
subscription-wide resource-provider validation lookup. Terraform mock tests inspect this graph;
they cannot prove Microsoft Entra principal resolution or Azure authorization.

## Azure topology and inputs

The deployment creates a `10.42.0.0/16` VNet, a `10.42.1.0/24` subnet, an explicit
`0.0.0.0/0 -> Internet` user-defined route and subnet association, a Standard static IPv4 address,
a NIC with an attached NSG, and one Linux VM. Azure already supplies system Internet routing; unlike
an AWS VPC, no customer-created Internet gateway is attached. The explicit route records the intended
egress next hop and Azure still computes the effective route from system, user-defined, and propagated
routes.

The NSG permits public TCP/80, permits TCP/22 only from one validated non-wildcard IPv4 `/32`, then
explicitly denies other inbound traffic before Azure's default NSG rules. An NSG is stateful and may
be attached to a subnet or NIC; this configuration attaches it to the VM NIC. This differs from an
AWS security group and must be reviewed through Azure's effective rules during a live run.

Required deployment inputs are an approved subscription UUID, existing resource-group name, explicit
Azure region, VM size, trusted admin `/32`, public SSH key, and exact Ubuntu Marketplace image version.
`latest` is rejected. The image is Canonical Ubuntu 22.04 Gen2, password authentication is disabled,
and only one syntactically valid OpenSSH RSA or Ed25519 public key is accepted. Local variable
validation checks syntax only. During a real plan the AzureRM provider parses the key and enforces its
supported key requirements, including RSA keys of at least 2048 bits. The OS disk requests `30 GiB`
Standard LRS with ReadWrite caching; local mocks do not observe the selected image's actual minimum
disk requirement or the created disk. VM size, image availability, regional quota, price, and
subscription policy require live review; no free-tier eligibility is claimed.

`cloud-init.yaml` performs the actual intended Ubuntu bootstrap: package metadata update, Nginx
installation, an `OK` health file, an index page, and service enablement. Terraform checks that the
VM receives those exact file bytes, while the disposable build-stage check validates and executes
the rendered command payload under the bounded stubs described above. The QEMU verifier serves the
repository's static site from Alpine and does **not** install or run cloud-init; it therefore does
**not** prove Ubuntu cloud-init boot, package installation, systemd behavior, managed-disk behavior,
or Azure networking.

## Deliberate live-cloud follow-up

These commands are instructions for a separately approved subscription, roles, budget, and source
address. Do not run them as part of local verification. Do not commit `terraform.tfvars`, plans, or
state. Review and secure Terraform state storage before a shared or durable deployment.

1. An authorized subscription operator preregisters `Microsoft.Network` and `Microsoft.Compute`,
   selects an exact approved Marketplace image version available in the target region, and records
   those decisions outside the restricted learner role.
2. The authorized role manager copies `access-bootstrap/terraform.tfvars.example` to an ignored
   `terraform.tfvars`, replaces every synthetic value, authenticates deliberately, then runs:
   `terraform init -lockfile=readonly`, `terraform plan -out=bootstrap.tfplan`, reviews the plan,
   and explicitly runs `terraform apply bootstrap.tfplan`.
3. After role propagation, the restricted deployer repeats the reviewed `init`, saved-plan, and
   explicit apply flow in `infrastructure/deployment/`, using the operator-selected exact image
   version; never substitute `latest`.
4. Inspect effective routes and NSG rules, cloud-init status, managed-disk size, public IP, SSH from
   the approved address, and `/health` from an appropriate external client. Boot diagnostics are not
   configured by this project and are not part of its automated evidence.
5. Destroy the deployment root first with a reviewed `terraform plan -destroy -out=destroy.tfplan`
   and explicit `terraform apply destroy.tfplan`. Only the authorized role manager then destroys the
   bootstrap root after checking for retained resources and cost records.

No script in this subtree automatically plans, applies, or destroys real Azure resources. See
[docs/REVIEW.md](docs/REVIEW.md) and [docs/cleanup-checklist.md](docs/cleanup-checklist.md). Required
cloud screenshots or reports must come from an actual authorized run. They are submission exceptions;
normally keep generated evidence in ignored artifacts or CI because it becomes stale and can expose
addresses or identity metadata.
