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

wget -qO /tmp/health-response "$WEB_URL/health"
cmp /work/web/health /tmp/health-response
wget -qO /tmp/index-response "$WEB_URL/"
cmp /work/web/index.html /tmp/index-response
printf 'OK\n' | cmp - /work/cloud-init-output/health
test "$(cat /work/cloud-init-output/apt-get.calls)" = 'install -y nginx'
test "$(cat /work/cloud-init-output/systemctl.calls)" = 'enable --now nginx'
if wget -qO /dev/null "$WEB_URL/not-present" 2>/tmp/not-present-error; then
  printf 'Missing path unexpectedly returned success\n' >&2
  exit 1
fi
grep -q '404' /tmp/not-present-error
if test "${VERIFY_MODE:-docker}" = vm; then
  wget -qO- "$WEB_URL/__vm-proof.txt" | grep -q '^kernel=Linux '
fi
printf 'PASS: pinned Terraform/AzureRM schema, exact payload, rendered cloud-init commands, bootstrap scope, invalid-input, and exact HTTP content\n'
printf 'LIMIT: local cloud-init rendering uses package/service stubs and does not prove an Ubuntu boot, Azure image availability, NSG dataplane, or RBAC enforcement\n'
