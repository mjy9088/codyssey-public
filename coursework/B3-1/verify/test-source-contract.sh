#!/bin/sh
set -eu

root=${1:?candidate root is required}
readme="$root/README.md"
review="$root/docs/REVIEW.md"
cleanup="$root/docs/cleanup-checklist.md"

require_pattern() {
  tr '\n' ' ' < "$2" | tr -s '[:space:]' ' ' | grep -Eiq -- "$1" || {
    printf 'Missing documented contract in %s: %s\n' "$2" "$1" >&2
    exit 1
  }
}

line_number() {
  grep -Fn -- "$1" "$2" | cut -d: -f1
}

for configuration in deployment access-bootstrap; do
  provider="$root/infrastructure/$configuration/versions.tf"
  test "$(grep -Fxc '  resource_provider_registrations = "none"' "$provider")" -eq 1
  test "$(grep -Fxc '    resource_providers = false' "$provider")" -eq 1
  test "$(grep -Fxc '      delete_os_disk_on_deletion = true' "$provider")" -eq 1
done

test "$(grep -Fc 'ARG TERRAFORM_LINUX_AMD64_SHA256=2bc2fcfff033265c9e02ca0351f01794eb122f62a9b2a49a3294b9e49eaab5e4' "$root/verify/Dockerfile")" -eq 1
test "$(grep -Fc 'ARG TERRAFORM_LINUX_ARM64_SHA256=61a50b00485ee4810cf20581ef080fc54d34d666e175c58d9a10501c65c1ccde' "$root/verify/Dockerfile")" -eq 1
test "$(grep -Fxc 'RUN apk add --no-cache cloud-init=24.3.1-r2' "$root/verify/Dockerfile")" -eq 1
test "$(grep -Fxc '**/*.tfvars' "$root/.dockerignore")" -eq 1
test "$(grep -Fxc '**/*.tfvars.json' "$root/.dockerignore")" -eq 1

deployment_plan=$(line_number 'terraform plan -destroy' "$cleanup")
deployment_apply=$(line_number 'apply that saved destroy plan' "$cleanup")
resource_review=$(line_number 'confirm deletion of the VM' "$cleanup")
bootstrap_destroy=$(line_number 'destroys the bootstrap root' "$cleanup")
if ! test "$deployment_plan" -lt "$deployment_apply" ||
   ! test "$deployment_apply" -lt "$resource_review" ||
   ! test "$resource_review" -lt "$bootstrap_destroy"; then
  printf 'Cleanup must destroy deployment resources before the bootstrap identity scope\n' >&2
  exit 1
fi
for resource in 'managed OS disk' NIC 'Standard public IP' NSG 'route.*table' subnet VNet 'role assignment' 'custom role' 'resource group'; do
  require_pattern "$resource" "$cleanup"
done
require_pattern 'retained.*disks or snapshots.*delayed cost records' "$cleanup"
require_pattern 'cannot prove cleanup or absence of charges' "$cleanup"

require_pattern 'without cloud credentials' "$readme"
require_pattern 'nothing here is evidence that Azure resources were created' "$readme"
require_pattern 'public endpoint was reached' "$readme"
require_pattern 'no customer-created Internet gateway is attached' "$readme"
require_pattern 'NSG.*differs from an AWS security group' "$readme"
require_pattern 'cannot prove Microsoft Entra principal resolution or Azure authorization' "$readme"
require_pattern 'not treat.*requested size.*observation.*created disk' "$review"
require_pattern 'selected region.*quota.*policy.*expected cost before an apply' "$review"
require_pattern 'never run live apply or destroy from local verification' "$review"

printf 'PASS: restricted provider, verifier pins, cleanup, and public limitation contracts\n'
