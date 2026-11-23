# Observe bounded synthetic memory, CPU, and thread scenarios; Linux only.
demo: check

# Compile into a temporary directory and exercise the synthetic resource lab.
check:
    #!/bin/sh
    set -eu
    test "$(uname -s)" = Linux || { echo 'Requires Linux /proc and procps.' >&2; exit 1; }
    build=$(mktemp -d)
    trap 'rm -rf "$build"' EXIT
    cc -std=c11 -O2 -Wall -Wextra -Werror -pthread fixture/resource-fixture.c -o "$build/resource-fixture"
    LAB_RESOURCE_FIXTURE="$build/resource-fixture" LAB_OUTPUT_DIR="$PWD/artifacts/native" sh tests/run.sh
