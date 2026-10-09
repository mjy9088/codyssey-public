#!/usr/bin/env bash
set -euo pipefail

for test_script in /src/tests/bootstrap-static.sh /src/tests/bootstrap-remote.sh /src/tests/bootstrap-runtime.sh; do
  bash "$test_script"
done
python3 /src/tests/macos-setup-test.py
printf 'PASS: isolated bootstrap and macOS preference checks completed\n'
