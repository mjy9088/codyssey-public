#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
guest=$root/verify/private/guest-init
public_verifier=$root/scripts/verify.sh
private_verifier=$root/scripts/verify-private.sh

grep -Fqx 'key_path="$agent_home/api_keys/secret.key"' "$guest"
grep -Fqx "printf 'agent_api_key_test\\n' > \"\$key_path\"" "$guest"
grep -Fqx '[[ $(wc -l < "$key_path") -eq 1 ]]' "$guest"
grep -Fqx '[[ $(cat "$key_path") == agent_api_key_test ]]' "$guest"
grep -Fqx "[[ \$(stat -c '%U:%G %a' \"\$key_path\") == 'agent-admin:agent-core 640' ]]" "$guest"
grep -Fq 'AGENT_KEY_PATH=$agent_home/api_keys' "$guest"
if grep -Fq 'api_keys/t_secret.key' "$guest"; then
  printf 'private guest must create only secret.key\n' >&2
  exit 1
fi

grep -Fq '.local/B4-1/agent-app.zip' "$public_verifier"
grep -Fq 'exec sh "$root/scripts/verify-private.sh" "$archive" "$evidence"' "$public_verifier"
if [[ -f $private_verifier ]]; then
  grep -Fq -- '--network none' "$private_verifier"
  grep -Fq 'docker cp "$input" "$container:/private-input/input.zip"' "$private_verifier"
  grep -Fq 'timeout --signal=TERM --kill-after=15s 180s docker start' "$private_verifier"
fi
grep -Fq 'DOCKER-VERIFY-SUCCESS (synthetic target only)' "$public_verifier"
grep -Fq 'VM-VERIFY-SUCCESS (synthetic target, genuine OS controls)' "$public_verifier"

printf 'PRIVATE-CONTRACT-SUCCESS (static inspection only; supplied target not executed)\n'
