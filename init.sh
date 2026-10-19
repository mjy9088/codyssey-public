#!/bin/sh
set -eu

case ${1:-} in
  '') [ "$#" -eq 0 ] || exit 2 ;;
  --help|-h) printf '%s\n' 'Usage: sh init.sh' 'Start the Codyssey environment from this checkout or the latest public main branch.'; exit 0 ;;
  *) printf 'Usage: sh init.sh\n' >&2; exit 2 ;;
esac

if [ -f "$0" ]; then
  case $0 in */*) source_dir=${0%/*} ;; *) source_dir=. ;; esac
  source_dir=$(CDPATH= cd -- "$source_dir" && pwd -P)
  local_init=$source_dir/environment/codyssey-init/init.sh
  if [ -f "$local_init" ]; then
    exec bash "$local_init"
  fi
fi

for dependency in curl mktemp bash; do
  command -v "$dependency" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$dependency" >&2; exit 1; }
done
installer=$(mktemp "${TMPDIR:-/tmp}/codyssey-init.XXXXXX")
cleanup() { rm -f "$installer"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
curl -fsSL "https://raw.githubusercontent.com/mjy9088/codyssey-public/main/environment/codyssey-init/init.sh" -o "$installer"
set +e
bash "$installer"
status=$?
set -e
cleanup
trap - 0 HUP INT TERM
exit "$status"
