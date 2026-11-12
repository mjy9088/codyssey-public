#!/usr/bin/env python3
"""Exercise interrupted writes, failed app installs, and actual service readiness."""
import os
import pty
import select
import time
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def executable(path, body):
    path.write_text('#!/bin/sh\n' + body + '\n')
    path.chmod(0o700)


class InstallerRecoveryTests(unittest.TestCase):
    def test_ghostty_failure_then_retry_and_existing_app_preservation(self):
        for failure in ('download', 'checksum', 'copy'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                home, tools = work/'home', work/'bin'
                home.mkdir()
                tools.mkdir()
                executable(tools/'uname', 'echo Darwin')
                executable(tools/'curl', '''[ "$FAILURE" != download ] || exit 22
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then echo dmg > "$2"; exit 0; fi
  shift
done
exit 1''')
                executable(tools/'shasum', '''if [ "$FAILURE" = checksum ]; then echo invalid; else
  echo '3a02075dbd24318d778426af41dee5507d53ecc4578ede96912ec9ce6d18d3e8  file'
fi''')
                executable(tools/'plistbuddy', '''case "$2" in
  *Identifier) echo com.mitchellh.ghostty ;;
  *VersionString) echo 1.4.0 ;;
  *) exit 1 ;;
esac''')
                executable(tools/'hdiutil', '''[ "$1" = attach ] || exit 0
while [ "$#" -gt 0 ]; do
  if [ "$1" = -mountpoint ]; then
    mkdir -p "$2/Ghostty.app/Contents/MacOS"
    echo ghostty > "$2/Ghostty.app/Contents/MacOS/ghostty"
    chmod 700 "$2/Ghostty.app/Contents/MacOS/ghostty"
    exit 0
  fi
  shift
done
exit 1''')
                executable(tools/'ditto', '''cp -R "$1" "$2"
[ "$FAILURE" != copy ] || exit 29''')
                env = dict(os.environ, HOME=str(home), PATH=str(tools)+':/usr/bin:/bin',
                           FAILURE=failure, PLISTBUDDY_BIN=str(tools/'plistbuddy'),
                           CODYSSEY_APPLICATIONS_DIR=str(work/'Applications'))
                command = ['/bin/bash', str(ROOT/'scripts/install-ghostty.sh')]
                result = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                target = home/'Applications/Ghostty.app'
                self.assertFalse(target.exists())
                self.assertEqual(list(home.glob('Applications/.codyssey-ghostty.*')), [])
                env['FAILURE'] = ''
                result = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                binary = target/'Contents/MacOS/ghostty'
                before = binary.read_bytes()
                env['FAILURE'] = 'download'
                again = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertEqual(again.returncode, 0, again.stderr)
                self.assertEqual(binary.read_bytes(), before)

    def test_shell_failed_write_preserves_symlink_and_retry_has_no_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            tools = work/'bin'
            tools.mkdir()
            target = work/'user-config'
            original = '# user settings\nexport USER_VALUE=keep\n'
            target.write_text(original)
            (work/'.zshrc').symlink_to(target)
            executable(tools/'cat', 'head -n 2; exit 37')
            env = dict(os.environ, HOME=str(work), PATH=str(tools)+':/usr/bin:/bin')
            env.pop('ZDOTDIR', None)
            command = ['/bin/bash', str(ROOT/'scripts/configure-shell.sh')]
            failed = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(failed.returncode, 37)
            self.assertEqual(target.read_text(), original)
            self.assertTrue((work/'.zshrc').is_symlink())
            env['PATH'] = '/usr/bin:/bin'
            for _ in range(2):
                subprocess.run(command, env=env, check=True, capture_output=True)
            text = target.read_text()
            self.assertTrue(text.startswith(original))
            self.assertEqual(text.count('# codyssey-init: mise\n'), 1)
            self.assertEqual(text.count('# codyssey-init: OrbStack tools\n'), 1)
            self.assertEqual(list(work.glob('.codyssey-zshrc.*')), [])

    def test_auth_failed_write_does_not_publish_partial_env(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, CODYSSEY_TTY_PATH=directory+'/absent')
            env.pop('TS_AUTHKEY', None)
            driver = '''. "$1/lib/auth.sh"
printf() { command printf "$@"; [ "$1" != 'TS_AUTHKEY=%s\\n' ]; }
if configure_tailscale_auth; then exit 9; fi
[ ! -e .env ] && [ -z "${auth_env_temporary:-}" ]'''
            result = subprocess.run(['/bin/bash', '-c', driver, 'test', str(ROOT)],
                                    cwd=directory, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(Path(directory).glob('.env.codyssey.*')), [])
            subprocess.run(['/bin/bash', '-c', '. "$1/lib/auth.sh"; configure_tailscale_auth', 'test', str(ROOT)],
                           cwd=directory, env=env, check=True, capture_output=True)
            path = Path(directory)/'.env'
            self.assertEqual(path.read_text(), 'TS_AUTHKEY=\n')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_saved_auth_can_retry_with_browser_or_new_key_without_overwrite(self):
        for replacement in ('', 'tskey'+'-auth-synthetic_retry_value'):
            with self.subTest(browser=not replacement), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                saved = 'TS_AUTHKEY=preserve-saved-credential\n'
                (work/'.env').write_text(saved)
                env = dict(os.environ, EXPECTED_AUTH=replacement)
                env.pop('TS_AUTHKEY', None)
                env.pop('CODYSSEY_TTY_PATH', None)
                driver = '. "$1/lib/auth.sh"; configure_tailscale_auth || exit; [ "${TS_AUTHKEY+x}" = x ] && [ "$TS_AUTHKEY" = "$EXPECTED_AUTH" ] || exit 2; echo RETRY_CONFIRMED'
                pid, terminal = pty.fork()
                if pid == 0:
                    os.chdir(work)
                    os.execvpe('/bin/bash', ['bash', '-c', driver, 'test', str(ROOT)], env)
                output, answered, status = b'', False, None
                try:
                    deadline = time.monotonic()+20
                    while time.monotonic() < deadline:
                        if select.select([terminal], [], [], 0.1)[0]:
                            try:
                                output += os.read(terminal, 65536)
                            except OSError:
                                pass
                            if not answered and b'blank for browser login' in output:
                                os.write(terminal, (replacement+'\n').encode())
                                answered = True
                        child, status = os.waitpid(pid, os.WNOHANG)
                        if child:
                            break
                        status = None
                    if status is None:
                        os.kill(pid, 9)
                        os.waitpid(pid, 0)
                        self.fail('Saved-auth retry prompt did not complete')
                    self.assertTrue(answered, output)
                    self.assertEqual(os.waitstatus_to_exitcode(status), 0, output)
                    self.assertEqual((work/'.env').read_text(), saved)
                    if replacement:
                        self.assertNotIn(replacement.encode(), output)
                finally:
                    os.close(terminal)

    def test_actual_readiness_rejects_missing_gost_or_failed_api(self):
        for failure in ('missing-gost', 'api'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                executable(work/'docker', '''case "$*" in
  *status*--json) echo '{"BackendState":"Running"}' ;;
  *) echo tailscale; echo gost-ui; [ "$FAILURE" = missing-gost ] || echo gost ;;
esac''')
                executable(work/'curl', '[ "$FAILURE" != api ]')
                executable(work/'sleep', 'exit 0')
                env = dict(os.environ, PATH=str(work)+':/usr/bin:/bin', FAILURE=failure)
                result = subprocess.run(['/bin/zsh', '-f', '-c',
                    '. "$1/lib/readiness.zsh"; ui_url=http://localhost:18081/; wait_for_tailnet || exit 9; wait_for_gost_ui',
                    'test', str(ROOT)], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn('GOST API/UI did not become ready', result.stderr)


if __name__ == '__main__':
    unittest.main()
