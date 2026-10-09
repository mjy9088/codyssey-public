#!/usr/bin/env bash
set -euo pipefail
root=/src
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ref=0123456789abcdef0123456789abcdef01234567
fakebin="$tmp/bin"
mkdir -p "$fakebin"

cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
output=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output=$2; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
relative=${url#*/environment/codyssey-init/}
if [ "${FAIL_FILE:-}" = "$relative" ]; then
  printf 'touch "$INITIAL_EXECUTED"\n' >"$output"
  exit 22
fi
source_file="$REMOTE_SOURCE/$relative"
[ -f "$source_file" ] || exit 22
cp "$source_file" "$output"
EOF
cat >"$fakebin/docker" <<'EOF'
#!/bin/sh
[ "$1" = info ]
EOF
cat >"$fakebin/mise" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/zsh" <<'EOF'
#!/bin/sh
printf 'zsh %s\n' "$*" >>"$REMOTE_LOG"
EOF
chmod 0755 "$fakebin"/*

# A failed initial download may have written executable shell text. The documented
# download-then-run contract must not execute that incomplete file.
download_then_run() (
  installer=$(mktemp) || exit 1
  trap 'rm -f "$installer"' EXIT
  curl --fail --location --silent --show-error \
    "https://example.invalid/repository/$ref/environment/codyssey-init/init.sh" \
    -o "$installer" && bash "$installer"
)
if PATH="$fakebin:/usr/bin:/bin" FAIL_FILE=init.sh REMOTE_SOURCE=$root \
  INITIAL_EXECUTED="$tmp/initial-executed" download_then_run; then
  printf 'failed initial download unexpectedly succeeded\n' >&2
  exit 1
fi
[[ ! -e "$tmp/initial-executed" ]] || { printf 'partial installer ran\n' >&2; exit 1; }

run_pipe() {
  HOME=$1 CODYSSEY_INIT_DIR=$2 CODYSSEY_INIT_BASE_URL=https://example.invalid/repository \
    CODYSSEY_INIT_REF=$ref PATH="$fakebin:/usr/bin:/bin" REMOTE_SOURCE=$root \
    REMOTE_LOG="$tmp/remote.log" TMPDIR=$3 bash <"$root/init.sh"
}

home="$tmp/home"
target="$tmp/install"
stage="$tmp/stage"
mkdir -p "$home" "$stage" "$target/gost"
printf 'TS_AUTHKEY=preserved\n' >"$target/.env"
printf 'services: [preserved]\n' >"$target/gost/gost.yaml"
run_pipe "$home" "$target" "$stage"
for file in init.sh verify-macos-setup.py next-script.zsh lib/auth.sh Dockerfile; do
  [[ -f "$target/$file" ]] || { printf 'missing remote file: %s\n' "$file" >&2; exit 1; }
done
grep -qx 'TS_AUTHKEY=preserved' "$target/.env"
grep -qx 'services: \[preserved\]' "$target/gost/gost.yaml"
run_pipe "$home" "$target" "$stage"

printf 'locally modified\n' >"$target/tailnet.sh"
rm "$target/Dockerfile"
if run_pipe "$home" "$target" "$stage" >/dev/null 2>&1; then
  printf 'modified installer was overwritten\n' >&2
  exit 1
fi
[[ ! -e "$target/Dockerfile" ]] || { printf 'preflight copied before conflict\n' >&2; exit 1; }

failed="$tmp/failed"
failed_stage="$tmp/failed-stage"
mkdir -p "$failed_stage"
if FAIL_FILE=mise.toml run_pipe "$home" "$failed" "$failed_stage" >/dev/null 2>&1; then
  printf 'failed download unexpectedly succeeded\n' >&2
  exit 1
fi
[[ ! -e "$failed" ]] || { printf 'failed download copied target files\n' >&2; exit 1; }
[[ -z $(find "$failed_stage" -mindepth 1 -print -quit) ]] || { printf 'staging was not cleaned\n' >&2; exit 1; }
