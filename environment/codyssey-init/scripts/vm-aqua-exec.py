#!/usr/bin/env python3
"""Run one verification command as a temporary job in the guest's Aqua session."""

import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid


def interrupt(signum, _frame):
    raise SystemExit(128 + signum)


def run_in_aqua(command, timeout):
    work = Path(tempfile.mkdtemp(prefix="codyssey-aqua-"))
    label = "org.codyssey.verify." + uuid.uuid4().hex
    domain = f"gui/{os.getuid()}"
    plist = work / "job.plist"
    log = work / "output"
    result = work / "result"
    # Publish the result only after the child has finished and flushed its output.
    runner = r"""
status_path=$1
shift
"$@"
status=$?
printf '%s\n' "$status" > "$status_path.tmp" && mv "$status_path.tmp" "$status_path"
"""
    plist.write_bytes(plistlib.dumps({
        "Label": label,
        "LimitLoadToSessionType": "Aqua",
        "ProgramArguments": ["/bin/bash", "-c", runner, "codyssey-aqua", str(result), *command],
        "RunAtLoad": True,
        "StandardOutPath": str(log),
        "StandardErrorPath": str(log),
    }))

    status = 1
    log.touch(mode=0o600)
    deadline = time.monotonic() + timeout
    try:
        subprocess.run(
            ["/bin/launchctl", "bootstrap", domain, str(plist)],
            check=True, timeout=min(30, timeout),
        )
        with log.open("rb") as stream:
            while not result.exists():
                shutil.copyfileobj(stream, sys.stdout.buffer)
                sys.stdout.buffer.flush()
                if time.monotonic() >= deadline:
                    print("Aqua verification command timed out.", file=sys.stderr)
                    break
                time.sleep(0.5)
            else:
                status = int(result.read_text())
            shutil.copyfileobj(stream, sys.stdout.buffer)
            sys.stdout.buffer.flush()
    finally:
        # Bootstrap can have registered the job before its reply arrived.
        try:
            subprocess.run(
                ["/bin/launchctl", "bootout", f"{domain}/{label}"],
                check=True, timeout=30,
            )
        except (OSError, subprocess.SubprocessError):
            print(f"Could not confirm removal of the Aqua job. Inspect {work}.", file=sys.stderr)
            if status == 0:
                status = 1
        else:
            shutil.rmtree(work)
    return status


def main():
    if len(sys.argv) < 3 or sys.platform != "darwin" or os.getuid() == 0:
        return 2
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, interrupt)
    try:
        timeout = int(sys.argv[1])
        if timeout <= 0:
            raise ValueError("timeout must be positive")
        return run_in_aqua(sys.argv[2:], timeout)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"Aqua verification failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
