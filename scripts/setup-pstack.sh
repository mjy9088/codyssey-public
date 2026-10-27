#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec node "$script_directory/setup-pstack.mjs" "$@"
