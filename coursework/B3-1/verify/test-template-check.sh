#!/bin/sh
set -eu

root=${VERIFY_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python=${PYTHON:-python3}

"$python" "$root/verify/template_check.py" "$root/infrastructure/template.json" \
  "$root/infrastructure/deployer-policy.json" >/dev/null

"$python" - "$root/infrastructure/template.json" "$tmp/no-outputs.json" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    template = json.load(stream)
del template["Outputs"]["InstanceId"]
with open(destination, "w", encoding="utf-8") as stream:
    json.dump(template, stream)
PY
if "$python" "$root/verify/template_check.py" "$tmp/no-outputs.json" \
  "$root/infrastructure/deployer-policy.json" >/dev/null 2>&1; then
  printf 'template checker accepted a missing InstanceId output\n' >&2
  exit 1
fi

"$python" - "$root/infrastructure/template.json" "$tmp/unencrypted.json" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    template = json.load(stream)
template["Resources"]["WebInstance"]["Properties"]["BlockDeviceMappings"][0]["Ebs"]["Encrypted"] = False
with open(destination, "w", encoding="utf-8") as stream:
    json.dump(template, stream)
PY
if "$python" "$root/verify/template_check.py" "$tmp/unencrypted.json" \
  "$root/infrastructure/deployer-policy.json" >/dev/null 2>&1; then
  printf 'template checker accepted an unencrypted termination volume\n' >&2
  exit 1
fi

"$python" - "$root/infrastructure/template.json" "$tmp/open-ssh-pattern.json" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    template = json.load(stream)
template["Parameters"]["SshSource"]["AllowedPattern"] = ".*"
with open(destination, "w", encoding="utf-8") as stream:
    json.dump(template, stream)
PY
if "$python" "$root/verify/template_check.py" "$tmp/open-ssh-pattern.json" \
  "$root/infrastructure/deployer-policy.json" >/dev/null 2>&1; then
  printf 'template checker accepted an unrestricted SSH parameter pattern\n' >&2
  exit 1
fi

printf 'PASS: template checker rejects missing outputs, unencrypted storage and unrestricted SSH input\n'
