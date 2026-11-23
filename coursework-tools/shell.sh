set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
web=false
case ${1-} in --web) web=true; shift ;; esac
case ${1-} in
  --) shift ;;
  -h|--help) printf '%s\n' 'Usage: sh .coursework-dev/shell.sh [--web] [-- COMMAND ...]'; exit 0 ;;
  '') ;;
  *) printf 'Expected -- before the command.\n' >&2; exit 2 ;;
esac
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker build --iidfile "$stage/image" --file .coursework-dev/Dockerfile .
set -- "$(cat "$stage/image")" "$@"
rm -rf "$stage"
trap - EXIT INT TERM
if [ "$web" = true ]; then set -- -p 127.0.0.1:8000:8000 "$@"; fi
if [ -t 0 ] && [ -t 1 ]; then set -- -it "$@"; fi
exec docker run --rm --init --cap-drop ALL --security-opt no-new-privileges --shm-size 1g "$@"
