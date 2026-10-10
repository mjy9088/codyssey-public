#!/usr/bin/env bash
set -euo pipefail
root=/src
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
work="$tmp/work"
cp -R "$root/." "$work"
fakebin="$tmp/bin"
home="$tmp/home"
mkdir -p "$fakebin" "$home"
log="$tmp/commands.log"

cat >"$fakebin/mise" <<'EOF'
#!/bin/sh
printf '<mise>' >>"$TEST_LOG"
for argument in "$@"; do printf '<%s>' "$argument" >>"$TEST_LOG"; done
printf '\n' >>"$TEST_LOG"
if [ "$1" = env ]; then printf 'export MISE_ENV_APPLIED=1\n'; fi
EOF
cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fakebin/open" <<'EOF'
#!/bin/sh
printf '<open>' >>"$TEST_LOG"
for argument in "$@"; do printf '<%s>' "$argument" >>"$TEST_LOG"; done
printf '\n' >>"$TEST_LOG"
exit 0
EOF
cat >"$fakebin/sleep" <<'EOF'
#!/bin/sh
printf '<sleep><%s>\n' "$1" >>"$TEST_LOG"
EOF
chmod 0755 "$fakebin"/*

write_runtime_docker() {
  cat >"$fakebin/docker" <<'EOF'
#!/bin/sh
printf '<docker>' >>"$TEST_LOG"
for argument in "$@"; do printf '<%s>' "$argument" >>"$TEST_LOG"; done
printf '<auth=%s><mise=%s>\n' "${TS_AUTHKEY:-}" "${MISE_ENV_APPLIED:-}" >>"$TEST_LOG"
case "$*" in
  'compose ps --status running --services') printf 'tailscale\ngost\ngost-ui\n' ;;
  'compose exec -T tailscale tailscale status --json') printf '{"BackendState":"%s"}\n' "${NEXT_STATE:-Running}" ;;
  'compose logs --no-color tailscale')
    if [ -n "${LOGIN_READS_FILE:-}" ]; then
      count=0
      [ ! -f "$LOGIN_READS_FILE" ] || count=$(cat "$LOGIN_READS_FILE")
      count=$((count + 1))
      printf '%s\n' "$count" >"$LOGIN_READS_FILE"
      [ "$count" -gt "${LOGIN_DELAY:-0}" ] || exit 0
    fi
    [ "${NO_LOGIN_URL:-0}" != 1 ] || exit 0
    printf 'To authenticate, visit: https://login.tailscale.com/a/synthetic\n' ;;
esac
EOF
  chmod 0755 "$fakebin/docker"
}

export HOME="$home" PATH="$fakebin:/usr/bin:/bin" TEST_LOG="$log"
write_runtime_docker
TS_AUTHKEY=tskey-auth_exported-value NEXT_STATE=Running zsh "$work/next-script.zsh" </dev/null
[[ ! -e "$work/.env" ]] || { printf 'exported key created .env\n' >&2; exit 1; }
grep -q '<mise><install><just@1.43.0>' "$log"
grep -q '<auth=tskey-auth_exported-value><mise=1>' "$log"

printf 'TS_AUTHKEY=existing-value\n' >"$work/.env"
before=$(sha256sum "$work/.env")
NEXT_STATE=Running zsh "$work/next-script.zsh" </dev/null
[[ $(sha256sum "$work/.env") == "$before" ]] || { printf '.env changed\n' >&2; exit 1; }

rm "$work/.env"
NEXT_STATE=NeedsLogin zsh "$work/next-script.zsh" </dev/null >"$tmp/login.out"
grep -q 'https://login.tailscale.com/a/synthetic' "$tmp/login.out"
grep -qx 'TS_AUTHKEY=' "$work/.env"
[[ $(stat -c '%a' "$work/.env") == 600 ]]

# NeedsLogin is observable before the login URL is available on a real cold boot.
: >"$log"
TS_AUTHKEY='' NEXT_STATE=NeedsLogin LOGIN_DELAY=2 LOGIN_READS_FILE="$tmp/delayed-reads" \
  zsh "$work/next-script.zsh" </dev/null >"$tmp/delayed.out"
grep -q 'https://login.tailscale.com/a/synthetic' "$tmp/delayed.out"
[[ $(cat "$tmp/delayed-reads") == 3 ]]
[[ $(grep -c '<sleep><1>' "$log") == 2 ]]
if TS_AUTHKEY='' NEXT_STATE=NeedsLogin NO_LOGIN_URL=1 LOGIN_READS_FILE="$tmp/missing-reads" \
  zsh "$work/next-script.zsh" </dev/null >"$tmp/missing.out" 2>&1; then
  printf 'missing login URL incorrectly succeeded\n' >&2
  exit 1
fi
[[ $(cat "$tmp/missing-reads") == 60 ]]
grep -q 'no authentication URL is available' "$tmp/missing.out"

: >"$log"
TS_AUTHKEY='' NEXT_STATE=NeedsLogin CODYSSEY_OPEN_BROWSER=0 \
  zsh "$work/next-script.zsh" </dev/null >"$tmp/headless.out"
grep -q 'GOST UI:' "$tmp/headless.out"
if grep -q '<open>' "$log"; then
  printf 'headless bootstrap launched a browser\n' >&2
  exit 1
fi
: >"$log"
TS_AUTHKEY='' NEXT_STATE=NeedsLogin CODYSSEY_OPEN_BROWSER=1 \
  zsh "$work/next-script.zsh" </dev/null >"$tmp/browser.out"
grep -q '<open><https://login.tailscale.com/a/synthetic>' "$log"
grep -q '<open><-a><Google Chrome>' "$log"

source "$work/lib/auth.sh"
key=$(extract_tailscale_auth_key 'TS_AUTHKEY=tskey-auth-old_style_value-token_2 docker compose up')
[[ $key == tskey-auth-old_style_value-token_2 ]]
if extract_tailscale_auth_key 'TS_AUTHKEY=tskey-auth-valid_token.invalid' >/dev/null; then
  printf 'partial malformed key accepted\n' >&2
  exit 1
fi

cat >"$fakebin/docker" <<'EOF'
#!/bin/sh
printf '<docker>' >>"$TEST_LOG"
for argument in "$@"; do printf '<%s>' "$argument" >>"$TEST_LOG"; done
printf '\n' >>"$TEST_LOG"
case "$*" in
  'compose ps --status running --services') printf 'tailscale\n' ;;
  'compose exec -T tailscale sh -c command -v bash') exit "${BASH_PROBE_STATUS:-0}" ;;
  'compose exec -T tailscale bash') exit 17 ;;
  'compose exec -T tailscale ssh user name@host') exit 23 ;;
esac
EOF
chmod 0755 "$fakebin/docker"
: >"$log"
set +e
BASH_PROBE_STATUS=1 bash "$work/tailnet.sh"
status=$?
set -e
[[ $status -eq 17 ]]
grep -q '<docker><compose><build><tailscale>' "$log"
grep -q '<docker><compose><up><-d><--no-deps><--force-recreate><tailscale>' "$log"

: >"$log"
set +e
bash "$work/tailnet.sh" ssh 'user name@host'
status=$?
set -e
[[ $status -eq 23 ]]
grep -q '<docker><compose><exec><-T><tailscale><ssh><user name@host>' "$log"
if grep -Eq '<ps>|<build>|<sh><-c><command -v bash>' "$log"; then
  printf 'arbitrary command was probed or rebuilt\n' >&2
  exit 1
fi

write_runtime_docker
rm -f "$work/.env"
pty_output=$(printf 'tskey-auth-secret_value-token_2\n' | script -q -e -c \
  "before=\$(stty -g); zsh '$work/next-script.zsh'; result=\$?; after=\$(stty -g); [ \"\$before\" = \"\$after\" ] && [ \"\$result\" -eq 0 ] && printf 'TTY-RESTORED\\n'" /dev/null)
printable_output=$(printf '%s' "$pty_output" | tr -d '\r')
printf '%s\n' "$printable_output" | grep -q '^TTY-RESTORED$'

install_bin="$tmp/install-bin"
install_home="$tmp/install-home"
mkdir -p "$install_bin" "$install_home"
cat >"$install_bin/docker" <<'EOF'
#!/bin/sh
[ "$1" = info ]
EOF
cat >"$install_bin/zsh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$install_bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'arm64\n' ;;
esac
EOF
cat >"$install_bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$INSTALL_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    printf '#!/bin/sh\nexit 0\n' >"$2"
    exit 0
  fi
  shift
done
exit 2
EOF
cat >"$install_bin/shasum" <<'EOF'
#!/bin/sh
printf '41c4028257d30f5f5742c99247c461f417143d6c7301f167a0c185247c8f206e  %s\n' "$3"
EOF
chmod 0755 "$install_bin"/*
INSTALL_LOG="$tmp/install.log" HOME="$install_home" PATH="$install_bin:/usr/bin:/bin" \
  CODYSSEY_INIT_DIR="$work" bash "$work/init.sh"
[[ -x "$install_home/.local/bin/mise" ]]
grep -q 'releases/download/v2026.10.5/mise-v2026.10.5-macos-arm64' "$tmp/install.log"
