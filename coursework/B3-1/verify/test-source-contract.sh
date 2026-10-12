#!/bin/sh
set -eu

root=${1:?candidate root is required}

for configuration in deployment access-bootstrap; do
  provider="$root/infrastructure/$configuration/versions.tf"
  test "$(grep -Fxc '  resource_provider_registrations = "none"' "$provider")" -eq 1
  test "$(grep -Fxc '    resource_providers = false' "$provider")" -eq 1
  test "$(grep -Fxc '      delete_os_disk_on_deletion = true' "$provider")" -eq 1
done

test "$(grep -Fc 'ARG TERRAFORM_LINUX_AMD64_SHA256=2bc2fcfff033265c9e02ca0351f01794eb122f62a9b2a49a3294b9e49eaab5e4' "$root/verify/Dockerfile")" -eq 1
test "$(grep -Fc 'ARG TERRAFORM_LINUX_ARM64_SHA256=61a50b00485ee4810cf20581ef080fc54d34d666e175c58d9a10501c65c1ccde' "$root/verify/Dockerfile")" -eq 1
test "$(grep -Fxc '**/*.tfvars' "$root/.dockerignore")" -eq 1
test "$(grep -Fxc '**/*.tfvars.json' "$root/.dockerignore")" -eq 1
printf 'PASS: restricted provider, architecture checksum, and variable-file source contracts\n'
