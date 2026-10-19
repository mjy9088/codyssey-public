#!/usr/bin/env python3
"""Real fresh-profile and repeat-launch verification in a disposable macOS desktop."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def processes(profile):
    output = subprocess.check_output(['ps', '-axo', 'pid=,args='], text=True)
    matches = []
    for line in output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        pid, args = fields
        if 'Google Chrome for Testing' in args and f'--user-data-dir={profile}' in args and '--type=' not in args:
            matches.append((int(pid), args))
    return matches


def wait_for_browser(profile):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        found = processes(profile)
        if len(found) == 1:
            if '--remote-debugging-' in found[0][1]:
                raise RuntimeError('The normal browser retained a debugging flag')
            return found[0][0]
        time.sleep(0.2)
    raise RuntimeError('The normal browser did not become ready')


def stop(profile):
    # Only the browser main process with this unique, private profile is owned.
    for pid, _ in processes(profile):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if not processes(profile):
            return
        time.sleep(0.2)
    raise RuntimeError('Private test browser did not close; no forced termination attempted')


def main():
    if sys.argv[1:] != ['--disposable'] or sys.platform != 'darwin' or os.getuid() == 0:
        raise RuntimeError('Use --disposable as the macOS guest desktop user')
    root = Path(__file__).resolve().parents[1]
    os.umask(0o077)
    work = Path(tempfile.mkdtemp(prefix='codyssey-browser-test.', dir=Path.home()))
    profile = work / 'tailnet-chrome-profile'
    marker = work / 'tailnet-browser-setup-v1'
    env = dict(os.environ, CODYSSEY_BROWSER_SUPPORT_DIR=str(work),
               CODYSSEY_BROWSER_CACHE_DIR=str(Path.home() / 'Library/Caches/codyssey-init'), TS_AUTHKEY='')
    try:
        subprocess.run(['bash', str(root / 'scripts/tailnet-browser.sh'), 'about:blank'], env=env, check=True, timeout=180)
        pid = wait_for_browser(profile)
        if not marker.is_file() or (profile / 'DevToolsActivePort').exists():
            raise RuntimeError('Profile setup did not complete or left its debugging endpoint')
        first = marker.stat().st_mtime_ns
        subprocess.run(['bash', str(root / 'scripts/tailnet-browser.sh'), 'about:blank'], env=env, check=True, timeout=30)
        if wait_for_browser(profile) != pid or marker.stat().st_mtime_ns != first:
            raise RuntimeError('Unchanged relaunch restarted or reconfigured the browser')
    finally:
        try:
            stop(profile)
        except BaseException:
            print(f'Private browser profile retained at {work}', file=sys.stderr)
            raise
        shutil.rmtree(work)
    print('PASS: real fresh Chrome profile, extension setup, closed debugging endpoint and unchanged relaunch.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('Browser verification: ' + str(error), file=sys.stderr)
        sys.exit(1)
