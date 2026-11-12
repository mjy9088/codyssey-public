#!/usr/bin/env python3
"""Default-deny workstation options with real entry points and synthetic tools."""
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OptionTests(unittest.TestCase):
    def fixture(self, work):
        runtime, home, tools = work/'runtime', work/'home', work/'bin'
        shutil.copytree(ROOT, runtime)
        home.mkdir()
        tools.mkdir()
        calls = work/'calls'
        for name, content in {
            'uname': 'echo Darwin',
            'docker': 'echo docker >> "$CALLS"; exit 31',
            'mise': 'echo mise >> "$CALLS"',
        }.items():
            path = tools/name
            path.write_text('#!/bin/sh\n' + content + '\n')
            path.chmod(0o700)
        (runtime/'scripts/install-ghostty.sh').write_text('#!/bin/sh\necho ghostty >> "$CALLS"\n')
        (runtime/'macos-setup.sh').write_text(
            '#!/bin/sh\nprintf "preferences:%s:%s:%s\\n" "$CODYSSEY_DOCK_LAUNCHER" "$CODYSSEY_DOCK_SETUP" "$*" >> "$CALLS"\n')
        env = dict(os.environ, HOME=str(home), PATH=str(tools)+':/usr/bin:/bin', CALLS=str(calls))
        for name in ('CODYSSEY_TAILNET_SETUP', 'CODYSSEY_INSTALL_J', 'CODYSSEY_MACOS_SETUP',
                     'CODYSSEY_DOCK_SETUP', 'CODYSSEY_RUN_LOG', 'CODYSSEY_INIT_DIR', 'ZDOTDIR'):
            env.pop(name, None)
        return runtime, home, calls, env

    def assert_default_skips(self, runtime, home, calls, runs=1):
        self.assertEqual(calls.read_text().splitlines(), ['ghostty'] * runs)
        self.assertFalse((home/'.local/bin/j').exists())
        self.assertFalse((home/'.zshrc').exists())
        self.assertFalse((runtime/'.env').exists())
        self.assertFalse((home/'Library/Application Support/codyssey-init/Codyssey j.command').exists())
        log = next((home/'Library/Logs/codyssey-init').glob('run.*')).read_text()
        for stage in ('tailnet', 'j', 'preferences'):
            self.assertIn(stage+' skipped', log)

    def test_unattended_default_and_repeat_preserve_existing_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime, home, calls, env = self.fixture(Path(directory))
            command = ['/bin/bash', str(runtime/'init.sh')]
            result = subprocess.run(command, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_default_skips(runtime, home, calls)
            existing = {home/'.local/bin/j': 'user-owned command\n', home/'.zshrc': '# keep shell\n',
                        runtime/'.env': 'TS_AUTHKEY=keep-existing\n'}
            for path, text in existing.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            prior_log = next((home/'Library/Logs/codyssey-init').glob('run.*'))
            prior_content = prior_log.read_bytes()
            # An interactive shell can inherit the previous run's internal log
            # variable. A new public init invocation must still get its own log.
            env['CODYSSEY_RUN_LOG'] = str(prior_log)
            again = subprocess.run(command, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertEqual(prior_log.read_bytes(), prior_content)
            self.assertEqual(len(list((home/'Library/Logs/codyssey-init').glob('run.*'))), 2)
            for path, text in existing.items():
                self.assertEqual(path.read_text(), text)
            self.assertEqual(calls.read_text().splitlines(), ['ghostty', 'ghostty'])

    def test_enter_declines_all_three_prompts(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime, home, calls, env = self.fixture(Path(directory))
            for run_number in (1, 2):
                pid, terminal = pty.fork()
                if pid == 0:
                    os.execvpe('/bin/bash', ['bash', str(runtime/'init.sh')], env)
                output, answered, status = b'', 0, None
                try:
                    deadline = time.monotonic()+20
                    while time.monotonic() < deadline:
                        if select.select([terminal], [], [], 0.1)[0]:
                            try:
                                output += os.read(terminal, 65536)
                            except OSError:
                                pass
                            while output.count(b'[y/N] ') > answered:
                                os.write(terminal, b'\n')
                                answered += 1
                        child, status = os.waitpid(pid, os.WNOHANG)
                        if child:
                            break
                        status = None
                    if status is None:
                        os.kill(pid, 9)
                        os.waitpid(pid, 0)
                        self.fail('Optional prompts did not finish: '+output.decode(errors='replace'))
                    self.assertEqual(os.waitstatus_to_exitcode(status), 0, output)
                    self.assertEqual(answered, 3, output)
                    if run_number == 1:
                        self.assert_default_skips(runtime, home, calls)
                        existing = {home/'.local/bin/j': 'keep command\n', home/'.zshrc': '# keep shell\n',
                                    runtime/'.env': 'TS_AUTHKEY=keep-existing\n'}
                        for path, text in existing.items():
                            path.parent.mkdir(parents=True, exist_ok=True)
                            path.write_text(text)
                    else:
                        self.assertEqual(calls.read_text().splitlines(), ['ghostty', 'ghostty'])
                        for path, text in existing.items():
                            self.assertEqual(path.read_text(), text)
                finally:
                    os.close(terminal)

    def test_j_opt_in_without_tailnet_requests_only_launcher_preferences(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime, home, calls, env = self.fixture(Path(directory))
            env.update(CODYSSEY_TAILNET_SETUP='0', CODYSSEY_INSTALL_J='1', CODYSSEY_MACOS_SETUP='0')
            result = subprocess.run(['/bin/bash', str(runtime/'init.sh')], env=env,
                                    stdin=subprocess.DEVNULL, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((home/'.local/bin/j').is_file())
            self.assertIn('preferences:1:0:--desktop-only', calls.read_text())
            self.assertNotIn('docker', calls.read_text())

    def test_preferences_opt_in_does_not_install_j(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime, home, calls, env = self.fixture(Path(directory))
            env.update(CODYSSEY_TAILNET_SETUP='0', CODYSSEY_INSTALL_J='0', CODYSSEY_MACOS_SETUP='1')
            result = subprocess.run(['/bin/bash', str(runtime/'init.sh')], env=env,
                                    stdin=subprocess.DEVNULL, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('preferences:0::', calls.read_text())
            self.assertFalse((home/'.local/bin/j').exists())
            self.assertNotIn('docker', calls.read_text())
            self.assertNotIn('mise', calls.read_text())


if __name__ == '__main__':
    unittest.main()
