#!/usr/bin/env python3
"""Synthetic cold-start checks; never install apps or start a real engine."""
import os
import importlib.util
import plistlib
from pathlib import Path
import subprocess
import tempfile
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
                       CALLS=str(work/'calls'), READY=str(work/'ready'), SCENARIO=scenario)
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
                env.update(TS_AUTHKEY='', CODYSSEY_MACOS_SETUP='0', CODYSSEY_OPEN_BROWSER='0')
                command = ['/bin/bash', str(ROOT / 'init.sh')]
            else:
                command = ['/bin/bash', '-c', script, 'test', str(ROOT)]
            result = subprocess.run(command, env=env,
                                    text=True, capture_output=True, timeout=10)
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
        self.assertIn('Preparing environment', result.stdout)

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


class InstalledAppTests(unittest.TestCase):
    def fixture(self, work):
        spec = importlib.util.spec_from_file_location('image_check', ROOT / 'scripts/check-preinstalled-apps.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        home = work / 'home'
        apps = home / 'Applications'
        for path, identifier, version in (
            (apps / 'OrbStack.app', 'dev.kdrag0n.MacVirt', '2.2.4'),
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
