#!/bin/sh
set -eu
case ${1-} in init|check) operation=$1 ;; *) printf 'Usage: %s init|check\n' "$0" >&2; exit 2 ;; esac
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Ignore inherited Terraform flags, configuration, and cloud credentials. The checked-in
# suites use mock providers; neither init nor tests may use a remote state backend.
for configuration in deployment access-bootstrap; do
  directory=$root/infrastructure/$configuration
  tf() {
    env -i PATH="$PATH" HOME="$home" TF_CLI_CONFIG_FILE=/dev/null TF_IN_AUTOMATION=1 \
      terraform -chdir="$directory" "$@"
  }
  tf init -backend=false -lockfile=readonly
  if [ "$operation" = check ]; then
    tf fmt -check -diff
    tf validate
    tf test
  fi
done
