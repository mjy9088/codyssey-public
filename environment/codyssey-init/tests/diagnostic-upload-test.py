"""Exercise failure reporting through the bootstrap's real controlling terminal."""
import errno
import os
import pty
import select
import signal
import subprocess
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PROMPT = b"[Y/n]"


def run_terminal(command, env, answer):
    pid, terminal = pty.fork()
    if pid == 0:
        os.execvpe(command[0], command, env)

    output = bytearray()
    deadline = time.monotonic() + 10
    answered = False
    reaped = False
    try:
        while select.select([terminal], [], [], max(0, deadline - time.monotonic()))[0]:
            try:
                chunk = os.read(terminal, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not chunk:
                break
            output.extend(chunk)
            if PROMPT in output and answer is not None and not answered:
                os.write(terminal, answer)
                answered = True
        else:
            raise AssertionError(f"Timed out waiting for bootstrap: {bytes(output)!r}")
        _, status = os.waitpid(pid, 0)
        reaped = True
        return os.waitstatus_to_exitcode(status), bytes(output)
    finally:
        os.close(terminal)
        if not reaped:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)


def fake_tool(directory, name, script):
    tool = directory / name
    tool.write_text("#!/bin/sh\n" + script)
    tool.chmod(0o755)


with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    fake_tool(work, "uname", "printf 'Linux\\n'\n")
    fake_tool(work, "mise", "exit 0\n")
    fake_tool(work, "node", "exit 0\n")
    fake_tool(
        work,
        "docker",
        """case "$*" in
  'container inspect '*) exit 1 ;;
  'compose ps --status running --services') printf 'tailscale\\ngost\\ntunnel-ui\\n' ;;
  'compose exec -T tailscale tailscale status --json') printf '{"BackendState":"Running"}\\n' ;;
  *) printf 'synthetic private tool output\\n' >&2; exit 1 ;;
esac
""",
    )
    fake_tool(
        work,
        "curl",
        """for argument do endpoint=$argument; done
case "$endpoint" in
  http://127.0.0.1:18081/health) exit 0 ;;
  https://*) ;;
  *) exit 97 ;;
esac
case "$*" in
  *'Content-Type: application/octet-stream'*'--data-binary @-'*) ;;
  *) exit 97 ;;
esac
printf '%s' "$endpoint" >"$UPLOAD_DESTINATION"
cat >"$UPLOAD_BODY"
printf '%s' "$UPLOAD_HTTP_STATUS"
""",
    )
    for case, tailnet, answer, http_status, expected_exit, should_upload in (
        ("default", "1", b"\n", "204", 1, True),
        ("declined", "1", b"n\n", "204", 1, False),
        ("eof", "1", b"\x04", "204", 1, False),
        ("http-error", "1", b"\n", "302", 1, True),
        ("continuation", "1", b"Y\n", "204", 1, True),
        ("headless", "1", None, "204", 1, False),
        ("success", "0", None, "204", 0, False),
    ):
        home = work / case
        upload = work / f"{case}.body"
        destination = work / f"{case}.destination"
        env = {
            "PATH": f"{work}:/usr/bin:/bin",
            "HOME": str(home),
            "CODYSSEY_TAILNET_SETUP": tailnet,
            "CODYSSEY_INSTALL_J": "0",
            "UPLOAD_BODY": str(upload),
            "UPLOAD_DESTINATION": str(destination),
            "UPLOAD_HTTP_STATUS": http_status,
        }
        command = ["bash", str(REPO / "init.sh")]
        if case == "continuation":
            unrelated = work / "unrelated.log"
            unrelated.write_text("synthetic unrelated file\n")
            env["CODYSSEY_RUN_LOG"] = str(unrelated)
            env["CODYSSEY_OPEN_BROWSER"] = "0"
            command = ["zsh", str(REPO / "next-script.zsh"), "--prepared"]
        if case == "headless":
            result = subprocess.run(command, env=env, input=b"\n", capture_output=True)
            status, output = result.returncode, result.stdout + result.stderr
        else:
            status, output = run_terminal(command, env, answer)
        assert status == expected_exit, (case, status, output)
        assert output.count(PROMPT) == (answer is not None), (case, output)
        assert upload.exists() == should_upload, (case, output)
        assert destination.exists() == should_upload, (case, output)
        if should_upload:
            (log,) = (home / "Library/Logs/codyssey-init").glob("run.*")
            payload = upload.read_bytes()
            assert b" to " + destination.read_bytes() + b"? " + PROMPT in output
            assert payload == log.read_bytes()
            assert b"run exit=1" in payload
            assert b"synthetic private tool output" not in payload
            assert (b"Diagnostic log sent." in output) == (http_status == "204")
            assert (b"Could not send diagnostic log" in output) == (http_status != "204")
