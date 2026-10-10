#!/usr/bin/env bash
set -euo pipefail

for test_script in /src/tests/bootstrap-static.sh /src/tests/bootstrap-remote.sh /src/tests/bootstrap-runtime.sh; do
  bash "$test_script"
done
if [[ ${CODYSSEY_NATIVE_PYTHON_CHECKS:-0} != 1 ]]; then
  python3 /src/tests/macos-setup-test.py
  python3 /src/tests/vm-orchestration-test.py
fi
printf 'PASS: isolated bootstrap checks completed\n'
