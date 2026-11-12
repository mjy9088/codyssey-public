#!/usr/bin/env python3
"""Synthetic cold-start checks; never install apps or start a real engine."""
import os
import importlib.util
import plistlib
from pathlib import Path
import subprocess
import tempfile
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ColdStartTests(unittest.TestCase):
    def run_case(self, scenario="cold", entrypoint=False, **overrides):
        with tempfile.TemporaryDirectory(prefix="orb-cold-") as directory:
            work = Path(directory)
            home = work / "home"
            fakebin = work / "bin"
            fakebin.mkdir()
            tools = home / "Applications/OrbStack.app/Contents/MacOS/xbin"
            tools.mkdir(parents=True)
            orb = tools.parent / "bin/orb"
            orb.parent.mkdir()
            orb.write_text('#!/bin/sh\necho "$1" >> "$CALLS"\n[ "$SCENARIO" != start-failure ] || exit 17\ntouch "$READY"\n')
            docker = tools / "docker"
            docker.write_text('#!/bin/sh\n[ "$SCENARIO" != timeout ] && [ -f "$READY" ]\n')
            for plugin in ("docker-compose", "docker-buildx"):
                path = tools / plugin
                path.write_text('#!/bin/sh\nexit 0\n')
                path.chmod(0o700)
            for name, source in {"uname": '#!/bin/sh\necho Darwin\n', "sleep": '#!/bin/sh\nexit 0\n'}.items():
                path = fakebin / name
                path.write_text(source)
                path.chmod(0o700)
            orb.chmod(0o700)
            docker.chmod(0o700)
            plugin_dir = home / '.docker/cli-plugins'
            plugin_dir.mkdir(parents=True)
            if scenario == 'existing-plugin':
                (plugin_dir / 'docker-compose').write_text('keep\n')
            if scenario == 'running':
                (fakebin / 'docker').write_text('#!/bin/sh\nexit 0\n')
                (fakebin / 'docker').chmod(0o700)
            env = dict(os.environ, HOME=str(home), PATH=str(fakebin)+':/usr/bin:/bin',
                       CODYSSEY_APPLICATIONS_DIR=str(work/'Applications'), CALLS=str(work/'calls'), READY=str(work/'ready'), SCENARIO=scenario)
            for key in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_CONFIG'):
                env.pop(key, None)
            env.update(overrides)
            script = 'die() { echo "$*" >&2; exit 1; }; . "$1/lib/bootstrap-tools.sh"; prepare_docker; docker info'
            if entrypoint:
                for name, content in {
                    'mise': '#!/bin/sh\nexit 0\n',
                    'zsh': '#!/bin/sh\nprintf "zsh %s\\n" "$*" >> "$CALLS"\n',
                }.items():
                    path = fakebin / name
                    path.write_text(content)
                    path.chmod(0o700)
                env.update(TS_AUTHKEY='', CODYSSEY_TAILNET_SETUP='1', CODYSSEY_INSTALL_J='0', CODYSSEY_MACOS_SETUP='0', CODYSSEY_OPEN_BROWSER='0')
                runtime = work / 'runtime'
                shutil.copytree(ROOT, runtime)
                (runtime / 'macos-setup.sh').write_text('#!/bin/sh\necho preferences >> "$CALLS"\n')
                (runtime / 'scripts/install-ghostty.sh').write_text('#!/bin/sh\necho ghostty >> "$CALLS"\n')
                env['CODYSSEY_MACOS_SETUP'] = '1'
                command = ['/bin/bash', str(runtime / 'init.sh')]
            else:
                command = ['/bin/bash', '-c', script, 'test', str(ROOT)]
            result = subprocess.run(command, env=env,
                                    text=True, capture_output=True, timeout=10)
            if entrypoint:
                # Exercise the same failed/successful install twice in one home.
                again = subprocess.run(command, env=env, text=True, capture_output=True, timeout=10)
                self.assertEqual(again.returncode, result.returncode, again.stderr)
                self.shell_state = (home / '.zshrc').read_text()
                self.logs = [(p.stat().st_mode & 0o777, p.read_text()) for p in (home / 'Library/Logs/codyssey-init').glob('run.*')]
            calls = (work/'calls').read_text() if (work/'calls').exists() else ''
            plugins = {p.name: str(p.readlink()) if p.is_symlink() else p.read_text() for p in plugin_dir.iterdir()}
            return result, calls, plugins

    def test_missing_docker_uses_bundled_cli_and_registers_plugins(self):
        result, calls, plugins = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, 'start\n')
        self.assertTrue(plugins['docker-compose'].endswith('/xbin/docker-compose'))
        self.assertTrue(plugins['docker-buildx'].endswith('/xbin/docker-buildx'))

    def test_full_installer_reaches_prepared_zsh_from_missing_docker(self):
        result, calls, plugins = self.run_case(entrypoint=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(calls.startswith('start\n'))
        self.assertIn('--prepared', calls)
        self.assertIn('docker-compose', plugins)
        self.assertIn('Preparing optional Tailnet environment', result.stdout)

    def test_failed_engine_still_applies_independent_steps_on_repeat(self):
        result, calls, _ = self.run_case('start-failure', entrypoint=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls.count('preferences\n'), 2)
        self.assertEqual(calls.count('ghostty\n'), 2)
        self.assertNotIn('--prepared', calls)
        self.assertEqual(self.shell_state.count('# codyssey-init: mise\n'), 1)
        self.assertEqual(self.shell_state.count('# codyssey-init: OrbStack tools\n'), 1)
        self.assertEqual(len(self.logs), 2)
        for mode, log in self.logs:
            self.assertEqual(mode, 0o600)
            self.assertIn('docker failed', log)
            self.assertIn('preferences ready', log)
            self.assertIn('run exit=1', log)
            self.assertNotIn('tskey-auth-', log)

    def test_existing_plugin_is_preserved(self):
        result, _, plugins = self.run_case('existing-plugin')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plugins['docker-compose'], 'keep\n')

    def test_working_engine_never_starts_orbstack(self):
        result, calls, plugins = self.run_case('running')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, '')
        self.assertEqual(plugins, {})

    def test_explicit_targets_are_never_replaced(self):
        for key in ('DOCKER_HOST', 'DOCKER_CONTEXT'):
            with self.subTest(key=key):
                result, calls, _ = self.run_case(**{key: 'synthetic-target'})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, '')

    def test_start_failure_and_timeout_are_reported(self):
        for scenario, message in (('start-failure', 'could not start'), ('timeout', '60 seconds')):
            with self.subTest(scenario=scenario):
                result, calls, _ = self.run_case(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertEqual(calls, 'start\n')


class ServiceRecoveryTests(unittest.TestCase):
    def test_service_failure_keeps_gost_check_and_secret_free_log_on_repeat(self):
        for failure in ('start', 'tailscale'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                runtime = work / 'runtime'
                shutil.copytree(ROOT, runtime)
                home = work / 'home'
                home.mkdir()
                fakebin = work / 'bin'
                fakebin.mkdir()
                (runtime / 'lib/readiness.zsh').write_text(
                    'wait_for_tailnet() { tailnet_state=; return 23; }\n'
                    'wait_for_gost_ui() { echo gost >> "$CALLS"; return 0; }\n')
                for name, body in {
                    'mise': 'exit 0',
                    'docker': 'echo compose >> "$CALLS"; [ "$FAILURE" != start ]',
                }.items():
                    path = fakebin / name
                    path.write_text('#!/bin/sh\n' + body + '\n')
                    path.chmod(0o700)
                env = dict(os.environ, HOME=str(home), PATH=str(fakebin)+':/usr/bin:/bin',
                           CALLS=str(work/'calls'), FAILURE=failure, TS_AUTHKEY='tskey-auth-SYNTHETIC_SECRET',
                           CODYSSEY_OPEN_BROWSER='0', CODYSSEY_INTERACTIVE_SHELL='0')
                env.pop('CODYSSEY_RUN_LOG', None)
                for _ in range(2):
                    result = subprocess.run(['/bin/zsh', '-f', str(runtime/'next-script.zsh'), '--prepared'],
                                            env=env, text=True, capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn('GOST UI:', result.stdout)
                self.assertEqual((work/'calls').read_text().count('gost\n'), 2)
                logs = list((home/'Library/Logs/codyssey-init').glob('run.*'))
                self.assertEqual(len(logs), 2)
                for log in logs:
                    text = log.read_text()
                    self.assertIn('tailscale failed', text)
                    self.assertIn('gost ready', text)
                    self.assertIn('run exit=1', text)
                    self.assertNotIn('SYNTHETIC_SECRET', text)


class InstalledAppTests(unittest.TestCase):
    def fixture(self, work):
        spec = importlib.util.spec_from_file_location('image_check', ROOT / 'scripts/check-preinstalled-apps.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        home = work / 'home'
        apps = home / 'Applications'
        for path, identifier, version in (
            (apps / 'OrbStack.app', 'dev.kdrag0n.MacVirt', '2.2.4'),
            (apps / 'Ghostty.app', 'com.mitchellh.ghostty', '1.4.0'),
            (apps / 'Google Chrome.app', 'com.google.Chrome', '155.0'),
            (home / 'Library/Input Methods/Gureum.app', 'org.youknowone.inputmethod.Gureum', '1.13.2'),
        ):
            (path / 'Contents').mkdir(parents=True)
            (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier, 'CFBundleShortVersionString': version}))
        for name in ('bin/orb', 'xbin/docker', 'xbin/docker-compose', 'xbin/docker-buildx'):
            path = apps / 'OrbStack.app/Contents/MacOS' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('#!/bin/sh\nexit 0\n')
            path.chmod(0o700)
        system = work / 'System/Applications'
        (system / 'Utilities/Terminal.app').mkdir(parents=True)
        return module, home, work / 'Applications', work / 'Library/Input Methods', system

    def test_user_local_apps_and_bundled_plugins_are_recognized(self):
        with tempfile.TemporaryDirectory() as directory:
            module, *arguments = self.fixture(Path(directory))
            self.assertEqual([path.name for path in module.inspect(*arguments)], ['docker', 'docker-compose', 'docker-buildx'])

    def test_missing_plugin_rejected_before_running_any_app(self):
        with tempfile.TemporaryDirectory() as directory:
            module, *arguments = self.fixture(Path(directory))
            (arguments[0] / 'Applications/OrbStack.app/Contents/MacOS/xbin/docker-compose').unlink()
            with self.assertRaisesRegex(RuntimeError, 'not executable'):
                module.inspect(*arguments)

    def test_unexpected_bundle_identity_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            module, *arguments = self.fixture(Path(directory))
            info = arguments[0] / 'Applications/OrbStack.app/Contents/Info.plist'
            info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'synthetic.other-app'}))
            with self.assertRaisesRegex(RuntimeError, 'identity'):
                module.inspect(*arguments)

    def test_wrong_gureum_version_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            module, *arguments = self.fixture(Path(directory))
            info = arguments[0] / 'Library/Input Methods/Gureum.app/Contents/Info.plist'
            info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.youknowone.inputmethod.Gureum', 'CFBundleShortVersionString': '0.0'}))
            with self.assertRaisesRegex(RuntimeError, '1.13.2'):
                module.inspect(*arguments)


if __name__ == '__main__':
    unittest.main()
