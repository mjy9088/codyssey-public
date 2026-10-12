#!/bin/sh
set -eu

# Keep the streamed entry point POSIX; execute the complete Bash installer.
export CODYSSEY_INIT_BASE_URL=${CODYSSEY_INIT_BASE_URL:-https://raw.githubusercontent.com/mjy9088/codyssey-public}
if [ -z "${CODYSSEY_INIT_REF:-}" ]; then
  CODYSSEY_INIT_REF=$(curl -fsSL https://api.github.com/repos/mjy9088/codyssey-public/commits/main |
    sed -n 's/^  "sha": "\([0-9a-f]*\)",$/\1/p' | head -n 1)
  export CODYSSEY_INIT_REF
fi
case $CODYSSEY_INIT_REF in
  ''|*[!0-9a-f]*) printf 'Could not resolve the installer commit.\n' >&2; exit 1 ;;
esac
[ "${#CODYSSEY_INIT_REF}" -eq 40 ]
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT HUP INT TERM
curl -fsSL "$CODYSSEY_INIT_BASE_URL/$CODYSSEY_INIT_REF/environment/codyssey-init/init.sh" -o "$installer"
bash "$installer"
