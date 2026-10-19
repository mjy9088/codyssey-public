#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
guest=$root/verify/private/guest-init
public_verifier=$root/scripts/verify.sh

grep -Fqx 'key_path="$agent_home/api_keys/t_secret.key"' "$guest"
grep -Fqx "printf 'agent_api_key_test\\n' > \"\$key_path\"" "$guest"
grep -Fqx '[[ $(wc -l < "$key_path") -eq 1 ]]' "$guest"
grep -Fqx '[[ $(cat "$key_path") == agent_api_key_test ]]' "$guest"
grep -Fqx "[[ \$(stat -c '%U:%G %a' \"\$key_path\") == 'agent-admin:agent-core 640' ]]" "$guest"
grep -Fq 'AGENT_KEY_PATH=$key_path' "$guest"
if grep -Fq 'api_keys/secret.key' "$guest"; then
  printf 'private guest must create only t_secret.key\n' >&2
  exit 1
fi

if grep -Fq 'verify-private' "$public_verifier" || grep -Fq 'PRIVATE-VM-SUCCESS' "$public_verifier"; then
  printf 'public verifier must not invoke or accept supplied-target verification\n' >&2
  exit 1
fi
grep -Fq 'DOCKER-VERIFY-SUCCESS (synthetic target only)' "$public_verifier"
grep -Fq 'VM-VERIFY-SUCCESS (synthetic target, genuine OS controls)' "$public_verifier"

printf 'PRIVATE-CONTRACT-SUCCESS (static inspection only; supplied target not executed)\n'
