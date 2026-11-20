#!/usr/bin/env python3
"""Drive the guest's desktop input check over Tart's loopback VNC endpoint."""
import argparse
import io
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tarfile
import time
from urllib.parse import unquote, urlsplit

from vncdotool import api

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "enable-korean.swift",
    "macos-setup.sh",
    "scripts/install-gureum.sh",
    "sdk/cli.mts",
    "sdk/setup.mts",
    "scripts/verify-macos-vm.sh",
)
LAUNCHER = b"""#!/bin/bash
cd "$(dirname -- "$0")" || exit 1
umask 077
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
if ! command -v node >/dev/null; then
    if command -v mise >/dev/null && mise install node@24.11.1; then
        export CODYSSEY_VERIFY_NODE="$(mise where node@24.11.1)/bin/node"
    else
        printf 'Guest needs Node.js 22.18+ or mise.\\n' >&2
        printf '1\\n' > status
        exit 1
    fi
fi
/usr/bin/script -qF transcript /bin/bash scripts/verify-macos-vm.sh --disposable --input-desktop
printf '%s\n' "$?" > status
"""


def connect_vnc(tart_log: Path):
    matches = re.findall(r"VNC server is running at (vnc://\S+)", tart_log.read_text())
    if len(matches) != 1:
        raise RuntimeError("Expected one VNC endpoint from a fresh Tart run log.")
    endpoint = urlsplit(matches[0])
    if endpoint.hostname != "127.0.0.1" or endpoint.port is None or not endpoint.password:
        raise RuntimeError("The Tart VNC endpoint must be password-protected and bound to 127.0.0.1.")

    return api.connect(f"{endpoint.hostname}::{endpoint.port}", password=unquote(endpoint.password), timeout=10)


def run_check(vm: str, tart_log: Path, expect_recovery: bool = False, confirm_desktop: bool = False) -> None:
    tart = subprocess.check_output(("mise", "-C", str(ROOT), "-E", "vm", "which", "tart"), text=True).strip()

    def guest(*args: str, data: bytes | None = None) -> bytes:
        stdin = ("-i",) if data is not None else ()
        return subprocess.run(
            (tart, "exec", *stdin, vm, *args),
            input=data, stdout=subprocess.PIPE, check=True, timeout=60,
        ).stdout

    directory = guest("/usr/bin/mktemp", "-d", "/tmp/codyssey-input.XXXXXX").decode().strip()
    if not re.fullmatch(r"/tmp/codyssey-input\.[A-Za-z0-9]+", directory):
        raise RuntimeError("Unexpected guest verification directory.")
    client = None
    try:
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode="w") as archive:
            for path in FILES:
                archive.add(ROOT / path, arcname=path)
            launcher = tarfile.TarInfo("verify-input.command")
            launcher.mode = 0o700
            launcher.size = len(LAUNCHER)
            archive.addfile(launcher, io.BytesIO(LAUNCHER))
        guest("/usr/bin/tar", "-xf", "-", "-C", directory, data=payload.getvalue())
        client = connect_vnc(tart_log)
        guest("/usr/bin/open", "-a", "Terminal", f"{directory}/verify-input.command")
        if expect_recovery:
            print("Leave Allow pending until the guest displays recovery guidance.", flush=True)
            wait_for_guest(guest, directory, "Gureum is not selected yet.", timeout=300)
            print("Guest displayed recovery guidance. Choose Allow now.", flush=True)
        else:
            print("If macOS asks to activate Gureum, choose Allow in the disposable VM desktop.", flush=True)
        stages = (
            ("With Gureum selected", ("g", "k", "s", "space", "return")),
            ("Press Control-Space to switch", ("ctrl-space",)),
            ("Type abc and press Return", ("a", "b", "c", "return")),
            ("Press Control-Space again", ("ctrl-space",)),
            ("Type gks, then press Space", ("g", "k", "s", "space", "return")),
        )
        for index, (prompt, keys) in enumerate(stages):
            wait_for_guest(guest, directory, prompt, timeout=300 if index == 0 else 60)
            if index == 0:
                guest("/usr/bin/open", "-a", "Terminal")
                if confirm_desktop:
                    input("Dismiss any separate Input Monitoring dialog, then press Enter here to start typing: ")
                time.sleep(0.5)
            for key in keys:
                client.keyPress(key)
                time.sleep(0.25)
        wait_for_guest(guest, directory, None)
    finally:
        if client is not None:
            client.disconnect()
            api.shutdown()
        guest("/bin/rm", "-rf", directory)


def wait_for_guest(guest, directory: str, prompt: str | None, timeout: int = 60) -> None:
    transcript_path = shlex.quote(f"{directory}/transcript")
    status_path = shlex.quote(f"{directory}/status")
    deadline = time.monotonic() + timeout
    transcript = ""
    while time.monotonic() < deadline:
        status, _, transcript = guest(
            "/bin/sh", "-c",
            f"head -1 {status_path} 2>/dev/null || printf '\\n'; cat {transcript_path} 2>/dev/null || :",
        ).decode(errors="replace").partition("\n")
        if status:
            print(transcript, end="", flush=True)
            if prompt is not None or status != "0":
                raise RuntimeError(f"Guest verifier exited with status {status} while waiting for {prompt or 'completion'}.")
            return
        if prompt is not None and prompt in transcript:
            return
        time.sleep(1)
    print(transcript, end="", flush=True)
    raise RuntimeError(f"Timed out waiting for {prompt or 'completion'}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vm", help="Running disposable Tart VM with a logged-in desktop")
    parser.add_argument("tart_log", type=Path, help="Private log from tart run --no-graphics --vnc-experimental")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--expect-recovery", action="store_true", help="Wait for the real recovery message before approving")
    modes.add_argument("--capture", type=Path, help="Capture the guest screen to a local PNG")
    modes.add_argument("--click", type=int, nargs=2, metavar=("X", "Y"), help="Click coordinates from a guest screenshot")
    parser.add_argument("--confirm-desktop", action="store_true", help="Wait for the operator before sending the first keys")
    args = parser.parse_args()
    try:
        if args.capture is not None or args.click is not None:
            client = connect_vnc(args.tart_log)
            try:
                if args.capture is not None:
                    client.captureScreen(str(args.capture))
                else:
                    client.mouseMove(*args.click)
                    client.mousePress(1)
            finally:
                client.disconnect()
                api.shutdown()
        else:
            run_check(args.vm, args.tart_log, args.expect_recovery, args.confirm_desktop)
    except (EOFError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
