# Azure Network Review Guide

## Configuration review

- Confirm both Terraform roots require Terraform `1.16.5`, AzureRM `4.66.0`, unchanged dependency
  locks, `resource_provider_registrations = "none"`, and disabled enhanced resource-provider
  validation. Runtime checks must use `terraform init -lockfile=readonly` against the local mirror.
- Trace the VNet, subnet, route table, explicit Internet route, and subnet association by reference;
  names alone do not prove topology.
- Confirm the Standard public IPv4 address is static and connected to the VM NIC.
- Inspect all three custom inbound NSG rules: public TCP/80, TCP/22 from exactly one trusted IPv4 `/32`,
  and deny all other inbound traffic. Confirm there is no all-port allow.
- Confirm password login is disabled, the public key is an input, the Ubuntu 22.04 Gen2 image version
  is explicit rather than `latest`, and the OS disk requests 30 GiB Standard LRS with ReadWrite
  caching. Do not treat the requested size as an observation of the image minimum or created disk.
- Inspect `cloud-init.yaml` and its mock assertions for Nginx installation, the `OK` health artifact,
  and service enablement.
- Confirm the deployment uses a resource-group data lookup and contains no resource group, role
  definition, or role assignment resource.
- Confirm the bootstrap custom role is assignable only at the dedicated resource group, permits only
  the exact enumerated resource-group read/network/compute/disk operations, and grants no wildcard,
  data action, exclusion, or role administration. The exact list includes NSG/route-table joins and
  both NIC effective-route and effective-NSG inspection actions.

## Local evidence boundary

`terraform test` uses a named AzureRM mock backed by the real provider schema. It can detect graph,
configured-value, validation, cloud-init, output, and RBAC-scope regressions without credentials. It
does not contact Azure and cannot establish image or VM-size availability, resource-provider
registration, effective route selection, effective NSG rules, cloud-init completion, Microsoft Entra
principal resolution, role propagation, RBAC enforcement, quota, policy, price, or billing cleanup.

Docker mode proves the static site under Nginx. VM mode additionally proves a separate QEMU TCG Linux
guest and guest HTTP forwarding. Neither mode boots the Azure Ubuntu image or exercises its managed
disk, public IP, NIC, NSG, or bootstrap process. The public URL and external capture are intentionally
not fabricated.

## Authorized live review

- Have an authorized subscription operator preregister `Microsoft.Network` and `Microsoft.Compute`
  and select the exact Marketplace image version outside the restricted learner role.
- Verify the selected region, VM size, exact Marketplace image version, quota, policy, and expected
  cost before an apply.
- Have a pre-authorized role manager apply the bootstrap separately; do not give the deployer Owner,
  User Access Administrator, or permission to assign its own role.
- Review saved plans before each explicit apply. Never run live apply or destroy from local verification.
- In Azure, inspect effective routes and rules, cloud-init, managed disk and public IP properties,
  source-limited SSH, HTTP health, and outbound package access. Boot diagnostics are not configured
  or automated by this project.
- Follow the cleanup checklist and billing view rather than assuming Terraform state alone proves that
  no resource or charge remains.

Cloud-run evidence is an explicit submission exception. It becomes stale and may expose addresses or
identity metadata, so retain only the minimum approved evidence. Prefer rerunnable checks over committed
PASS logs.
