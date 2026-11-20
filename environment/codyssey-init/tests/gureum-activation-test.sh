#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
/usr/bin/swiftc -module-cache-path "$work/cache" -typecheck "$root/enable-korean.swift"
cat "$root/enable-korean.swift" "$root/tests/gureum-activation-test.swift" >"$work/scenarios.swift"
/usr/bin/swift -module-cache-path "$work/cache" -D CODYSSEY_INPUT_TEST "$work/scenarios.swift"
