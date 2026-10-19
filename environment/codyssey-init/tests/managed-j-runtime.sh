#!/usr/bin/env bash
set -euo pipefail
root=/src
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
work="$tmp/local source's"
cp -R "$root/." "$work"
fakebin="$tmp/bin"
home="$tmp/home"
mkdir -p "$fakebin" "$home"
python=$(command -v python3)

cat >"$fakebin/docker" <<'EOF'
#!/bin/sh
case "$*" in
  info|'compose build tailscale'|'compose pull gost gost-ui') exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat >"$fakebin/zsh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf 'Linux\n' ;;
  -m) printf 'x86_64\n' ;;
esac
EOF
cat >"$fakebin/mise" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/just" <<'EOF'
#!/bin/sh
printf 'cwd=<%s>\n' "$PWD" >"$JUST_LOG"
for argument in "$@"; do printf 'arg=<%s>\n' "$argument" >>"$JUST_LOG"; done
exit "${JUST_STATUS:-0}"
EOF
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
cp "$REMOTE_SOURCE/$relative" "$output"
EOF
chmod 0755 "$fakebin"/*

run_interactive_init() {
  local source=$1 answer=$2 output=$3
  printf '%s\n' "$answer" | INIT_SOURCE="$source" script -q -e -c \
    "HOME='$home' PATH='$fakebin:/usr/bin:/bin' bash \"\$INIT_SOURCE/init.sh\"" /dev/null >"$output" 2>&1
}

run_interactive_init "$work" yes "$tmp/install.out"
j="$home/.local/bin/j"
[[ $(sed -n '1p' "$j") == '#!/bin/sh' ]]
[[ $(sed -n '2p' "$j") == '# codyssey-init: managed-j-v1' ]]
[[ $(stat -c '%a' "$j") == 700 ]]

just_log="$tmp/just.log"
set +e
(cd "$tmp" && JUST_LOG="$just_log" JUST_STATUS=29 PATH="$fakebin:/usr/bin:/bin" \
  "$python" -c 'import subprocess, sys; raise SystemExit(subprocess.run([sys.argv[1], "two words", "*"]).returncode)' "$j")
status=$?
set -e
[[ $status -eq 29 ]]
grep -Fx "cwd=<$work>" "$just_log"
grep -Fx 'arg=<two words>' "$just_log"
grep -Fx 'arg=<*>' "$just_log"

first_wrapper=$(sha256sum "$j")
run_interactive_init "$work" Y "$tmp/repeat.out"
[[ $(sha256sum "$j") == "$first_wrapper" ]]

printf '%s\n' '# codyssey-init: managed-j-v1' '#!/bin/sh' 'exit 88' >"$j"
chmod 0700 "$j"
run_interactive_init "$work" YES "$tmp/migrate.out"
[[ $(sed -n '1p' "$j") == '#!/bin/sh' ]]
[[ $(sed -n '2p' "$j") == '# codyssey-init: managed-j-v1' ]]

ref=0123456789abcdef0123456789abcdef01234567
pipe_home="$tmp/pipe-home"
pipe_target="$tmp/remote target"
mkdir -p "$pipe_home"
printf 'yes\n' | INIT_SOURCE="$work/init.sh" script -q -e -c \
  "cat \"\$INIT_SOURCE\" | HOME='$pipe_home' PATH='$fakebin:/usr/bin:/bin' REMOTE_SOURCE='$root' CODYSSEY_INIT_DIR='$pipe_target' CODYSSEY_INIT_BASE_URL=https://example.invalid/repository CODYSSEY_INIT_REF=$ref bash" \
  /dev/null >"$tmp/pipe.out" 2>&1
pipe_j="$pipe_home/.local/bin/j"
[[ -x $pipe_j ]]
JUST_LOG="$just_log" PATH="$fakebin:/usr/bin:/bin" "$pipe_j"
grep -Fx "cwd=<$pipe_target>" "$just_log"

headless_home="$tmp/headless-home"
headless_target="$tmp/headless-target"
mkdir -p "$headless_home"
cat "$work/init.sh" | HOME="$headless_home" PATH="$fakebin:/usr/bin:/bin" REMOTE_SOURCE="$root" \
  CODYSSEY_INIT_DIR="$headless_target" CODYSSEY_INIT_BASE_URL=https://example.invalid/repository \
  CODYSSEY_INIT_REF=$ref bash >"$tmp/headless.out" 2>&1
[[ ! -e "$headless_home/.local/bin/j" ]]

negative_home="$tmp/negative-home"
mkdir -p "$negative_home"
printf 'n\n' | INIT_SOURCE="$work" script -q -e -c \
  "HOME='$negative_home' PATH='$fakebin:/usr/bin:/bin' bash \"\$INIT_SOURCE/init.sh\"" /dev/null >"$tmp/negative.out" 2>&1
[[ ! -e "$negative_home/.local/bin/j" ]]

conflict_home="$tmp/conflict-home"
mkdir -p "$conflict_home/.local/bin"
printf '#!/bin/sh\nprintf user-owned\\n\n' >"$conflict_home/.local/bin/j"
chmod 0755 "$conflict_home/.local/bin/j"
conflict_before=$(sha256sum "$conflict_home/.local/bin/j")
printf 'y\n' | INIT_SOURCE="$work" script -q -e -c \
  "HOME='$conflict_home' PATH='$fakebin:/usr/bin:/bin' bash \"\$INIT_SOURCE/init.sh\"" /dev/null >"$tmp/conflict.out" 2>&1
[[ $(sha256sum "$conflict_home/.local/bin/j") == "$conflict_before" ]]
grep -Fq "preserving existing unowned command at $conflict_home/.local/bin/j" "$tmp/conflict.out"
