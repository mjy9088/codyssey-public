#!/usr/bin/env bash
set -euo pipefail
node --test /src/tests/chrome-extension-test.mjs
if [[ ${CODYSSEY_NATIVE_PYTHON_CHECKS:-0} != 1 ]]; then
  python3 /src/tests/portable-browser-test.py
fi

for test_script in /src/tests/bootstrap-static.sh /src/tests/bootstrap-remote.sh /src/tests/bootstrap-runtime.sh \
  /src/tests/managed-j-runtime.sh; do
  bash "$test_script"
done
if [[ ${CODYSSEY_NATIVE_PYTHON_CHECKS:-0} != 1 ]]; then
  python3 /src/tests/macos-setup-test.py
  python3 /src/tests/vm-orchestration-test.py
fi
python3 /src/tests/vm-guest-test.py
printf 'PASS: isolated bootstrap checks completed\n'
