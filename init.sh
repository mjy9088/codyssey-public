#!/bin/sh
set -eu

DEFAULT_REF=5bf84e10d35a8f30d317e3bb8d61f80218922efc
DEFAULT_HTTPS_BASE=https://raw.githubusercontent.com/mjy9088/codyssey-public
REF=${CODYSSEY_INIT_REF:-$DEFAULT_REF}
HTTPS_BASE=${CODYSSEY_INIT_BASE_URL:-$DEFAULT_HTTPS_BASE}

show_docs() {
  printf '%s\n' 'Local documentation: environment/codyssey-init/README.md'
  printf 'Documentation for selected ref: %s/%s/environment/codyssey-init/README.md\n' \
    "${HTTPS_BASE%/}" "$REF"
}

show_help() {
  printf '%s\n' 'Usage: sh init.sh [--help | --docs]' \
    'Run without arguments to start the Codyssey environment bootstrap.' \
    'CODYSSEY_INIT_REF may select a reviewed full 40-character lowercase commit.' \
    'CODYSSEY_INIT_BASE_URL may select a reviewed HTTPS raw-content source.'
  show_docs
}

case ${1:-} in
  '') [ "$#" -eq 0 ] || { show_help >&2; exit 2; } ;;
  --help|-h) [ "$#" -eq 1 ] || { show_help >&2; exit 2; }; show_help; exit 0 ;;
  --docs) [ "$#" -eq 1 ] || { show_help >&2; exit 2; }; show_docs; exit 0 ;;
  *) show_help >&2; exit 2 ;;
esac

if [ -f "$0" ]; then
  case $0 in */*) source_dir=${0%/*} ;; *) source_dir=. ;; esac
  source_dir=$(CDPATH= cd -- "$source_dir" && pwd -P)
  local_init=$source_dir/environment/codyssey-init/init.sh
  if [ -f "$local_init" ]; then
    printf '%s\n' 'Using the environment bootstrap from this local checkout.'
    show_docs
    exec bash "$local_init"
  fi
fi

case $REF in ''|*[!0-9a-f]*) printf '%s\n' 'CODYSSEY_INIT_REF must be 40 lowercase hexadecimal characters.' >&2; exit 2 ;; esac
[ "${#REF}" -eq 40 ] || { printf '%s\n' 'CODYSSEY_INIT_REF must be 40 lowercase hexadecimal characters.' >&2; exit 2; }
case $HTTPS_BASE in https://*) ;; *) printf '%s\n' 'CODYSSEY_INIT_BASE_URL must use HTTPS.' >&2; exit 2 ;; esac
for dependency in curl mktemp bash; do
  command -v "$dependency" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$dependency" >&2; exit 1; }
done
export CODYSSEY_INIT_REF=$REF CODYSSEY_INIT_BASE_URL=${HTTPS_BASE%/}
show_docs
installer=$(mktemp "${TMPDIR:-/tmp}/codyssey-init.XXXXXX")
cleanup() { rm -f "$installer"; }
trap cleanup 0
trap 'exit 1' HUP INT TERM
curl -fsSL "$CODYSSEY_INIT_BASE_URL/$REF/environment/codyssey-init/init.sh" -o "$installer"
set +e
bash "$installer"
status=$?
set -e
cleanup
trap - 0 HUP INT TERM
exit "$status"
