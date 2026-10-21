#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
input=$tmp/input.zip
printf 'synthetic wrapper fixture\n' >"$input"
mkdir "$tmp/real-evidence"
ln -s "$input" "$tmp/input-link.zip"
ln -s "$tmp/real-evidence" "$tmp/evidence-link"

reject() {
  if PATH="$tmp/bin:$PATH" sh "$root/scripts/verify-private.sh" "$@" >/dev/null 2>&1; then
    printf 'unsafe private-wrapper path unexpectedly accepted: %s\n' "$*" >&2
    exit 1
  fi
}
mkdir "$tmp/bin"
cat >"$tmp/bin/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$DOCKER_LOG"
case "$1" in create) printf 'fixture-container\n' ;; esac
exit 0
EOF
chmod +x "$tmp/bin/docker"
reject relative.zip "$tmp/evidence"
reject "$tmp/input-link.zip" "$tmp/evidence"
reject "$input" "$tmp/evidence-link"
reject "$root/README.md" "$tmp/evidence"
reject "$input" "$root/tests"
forbidden_evidence=$root/tests/.private-wrapper-forbidden
[[ ! -e $forbidden_evidence ]]
reject "$input" "$forbidden_evidence"
[[ ! -e $forbidden_evidence ]]
truncate -s 52428801 "$tmp/oversize.zip"
reject "$tmp/oversize.zip" "$tmp/evidence"

: >"$tmp/docker.log"
set +e
DOCKER_LOG=$tmp/docker.log PATH="$tmp/bin:$PATH" \
  sh "$root/scripts/verify-private.sh" "$input" "$tmp/evidence" >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 1 ]]
create_line=$(grep -n '^create ' "$tmp/docker.log" | cut -d: -f1)
copy_line=$(grep -n '^cp ' "$tmp/docker.log" | cut -d: -f1)
[[ $create_line -lt $copy_line ]]
grep -q '^build -f .*/verify/private/Dockerfile -t .* .*/coursework/B4-1$' "$tmp/docker.log"
grep -q '^create .*--network none .*--memory 1536m .*--cpus 1.0 .*--pids-limit 256 .*--cap-drop ALL ' "$tmp/docker.log"
grep -q '^create .*--cap-add DAC_OVERRIDE ' "$tmp/docker.log"
[[ $(stat -c %a "$tmp/evidence") == 700 ]]
run_dirs=("$tmp/evidence"/run.*)
[[ ${#run_dirs[@]} -eq 1 && -d ${run_dirs[0]} ]]
run_dir=${run_dirs[0]}
[[ $(stat -c %a "$run_dir") == 700 ]]
[[ $(stat -c %a "$run_dir/serial.raw.log") == 600 ]]
[[ $(stat -c %a "$run_dir/serial.log") == 600 ]]
grep -Fqx '.local' "$root/.dockerignore"

fixture=$tmp/repo/coursework/B4-1
mkdir -p "$fixture/scripts" "$tmp/repo/.git" "$tmp/repo/.local/B4-1" "$tmp/repo/.local/evidence/B4-1"
cp "$root/scripts/verify-private.sh" "$fixture/scripts/verify-private.sh"
printf 'synthetic canonical-path fixture\n' >"$tmp/repo/.local/B4-1/agent-app.zip"
: >"$tmp/canonical-docker.log"
set +e
DOCKER_LOG=$tmp/canonical-docker.log PATH="$tmp/bin:$PATH" \
  sh "$fixture/scripts/verify-private.sh" "$tmp/repo/.local/B4-1/agent-app.zip" \
    "$tmp/repo/.local/evidence/B4-1" >/dev/null 2>&1
canonical_status=$?
set -e
[[ $canonical_status -eq 1 ]]
grep -q '^build ' "$tmp/canonical-docker.log"
printf 'PRIVATE-WRAPPER-GUARDS-SUCCESS (paths, size, Docker argv/order, evidence modes)\n'
