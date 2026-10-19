#!/usr/bin/env bash
set -euo pipefail

root=${TEST_ROOT:-/src}
auth_lib=${AUTH_LIB:-$root/lib/auth.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fakebin="$tmp/bin"
work="$tmp/work"
gate="$tmp/stty-gate"
mkdir -p "$fakebin" "$work"
mkfifo "$gate"
real_stty=$(command -v stty)

cat >"$fakebin/stty" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -echo ]; then
  printf '<ECHO-DISABLE-BARRIER>\n' >/dev/tty
  IFS= read -r _ <"$STTY_GATE"
fi
exec "$REAL_STTY" "$@"
EOF
chmod 0755 "$fakebin/stty"

AUTH_LIB="$auth_lib" TEST_WORK="$work" STTY_GATE="$gate" REAL_STTY="$real_stty" \
PATH="$fakebin:$PATH" python3 - <<'PY'
import errno
import fcntl
import os
import pathlib
import pty
import select
import shlex
import signal
import subprocess
import termios
import time

barrier = b"<ECHO-DISABLE-BARRIER>"
prompt = b"Tailscale auth key or install/up command (blank for browser login): "
restored = b"<TTY-RESTORED>"
secret = "tskey" + "-auth-synthetic_prompt_value"
work = pathlib.Path(os.environ["TEST_WORK"])
auth_lib = os.environ["AUTH_LIB"]
gate = os.environ["STTY_GATE"]
master, slave = pty.openpty()
transcript = bytearray()

def attach_terminal() -> None:
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

def read_until(token: bytes) -> None:
    deadline = time.monotonic() + 5
    while token not in transcript:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(f"timed out waiting for {token!r}: {bytes(transcript)!r}")
        readable, _, _ = select.select([master], [], [], remaining)
        if not readable:
            continue
        transcript.extend(os.read(master, 4096))

command = (
    f"cd {shlex.quote(str(work))}; "
    "before=$(stty -g); "
    f". {shlex.quote(auth_lib)}; "
    "configure_tailscale_auth; result=$?; "
    "after=$(stty -g); "
    "[ \"$before\" = \"$after\" ] && printf '<TTY-RESTORED>\\n'; "
    "exit \"$result\""
)
environment = os.environ.copy()
environment.pop("TS_AUTHKEY", None)
process = subprocess.Popen(
    ["bash", "-c", command],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    env=environment,
    preexec_fn=attach_terminal,
    close_fds=True,
)
os.close(slave)
try:
    read_until(barrier)
    before_barrier = bytes(transcript).split(barrier, 1)[0]
    assert prompt not in before_barrier, "auth prompt became visible before echo disable completed"
    with open(gate, "w", encoding="ascii") as gate_writer:
        gate_writer.write("continue\n")
    read_until(prompt)
    os.write(master, (secret + "\n").encode())
    deadline = time.monotonic() + 5
    while process.poll() is None and time.monotonic() < deadline:
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            try:
                transcript.extend(os.read(master, 4096))
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
    return_code = process.wait(timeout=1)
    while True:
        try:
            readable, _, _ = select.select([master], [], [], 0)
            if not readable:
                break
            transcript.extend(os.read(master, 4096))
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            break
    assert return_code == 0, f"auth helper exited {return_code}: {bytes(transcript)!r}"
    assert secret.encode() not in transcript, "secret was echoed into the rendered transcript"
    assert restored in transcript, "terminal state was not restored"
    assert (work / ".env").read_text(encoding="utf-8") == f"TS_AUTHKEY={secret}\n"
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    os.close(master)

print("PASS: auth prompt follows echo disable")
PY
