#!/bin/sh
set -eu
for credential in ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_TENANT_ID ARM_SUBSCRIPTION_ID AZURE_CONFIG_DIR; do
  eval "value=\${$credential-}"
  if test -n "$value"; then
    printf 'Refusing inherited Azure credential/config variable: %s\n' "$credential" >&2
    exit 1
  fi
done

for configuration in deployment access-bootstrap; do
  directory="/work/infrastructure/$configuration"
  terraform -chdir="$directory" init -backend=false -lockfile=readonly
  terraform -chdir="$directory" fmt -check -diff
  terraform -chdir="$directory" validate
  terraform -chdir="$directory" test
done

test "$(wget -qO- "$WEB_URL/health")" = OK
if wget -qO /dev/null "$WEB_URL/not-present" 2>/tmp/not-present-error; then
  printf 'Missing path unexpectedly returned success\n' >&2
  exit 1
fi
grep -q '404' /tmp/not-present-error
if test "${VERIFY_MODE:-docker}" = vm; then
  wget -qO- "$WEB_URL/__vm-proof.txt" | grep -q '^kernel=Linux '
fi
printf 'PASS: pinned Terraform/AzureRM schema, mock topology, bootstrap scope, invalid-input, and HTTP checks\n'
printf 'LIMIT: named Terraform mocks do not call Azure or prove image availability, cloud-init boot, NSG dataplane, or RBAC enforcement\n'
