#!/usr/bin/env python3
"""Protect existing profiles while configuring the selected default, without TCC."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('macos', ROOT/'tests/macos-setup-test.py')
macos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(macos)
DOMAIN = 'com.googlecode.iterm2'

class PreferencesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.env, self.state = macos.environment(self.work)
        fake = self.work/'bin'
        self.env['PATH'] = str(fake)+':'+os.environ['PATH']
        pgrep = fake/'pgrep'
        pgrep.write_text('#!/bin/sh\nexit "${ITERM_RUNNING:-1}"\n')
        pgrep.chmod(0o700)
        self.env['PGREP_BIN'] = str(pgrep)

    def run_setup(self, ok=True):
        result = subprocess.run(['/bin/bash', str(ROOT/'scripts/configure-iterm2.sh')],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout+result.stderr)
        return result

    def read(self): return macos.read_domain(self.state, DOMAIN)
    def write(self, data): macos.write_domain(self.state, DOMAIN, data)
    def backups(self): return list((Path(self.env['HOME'])/'Library/Application Support/codyssey-init/iterm2-backups').glob('run.*'))

    def test_first_install_repeat_and_private_backup(self):
        self.run_setup()
        before = macos.state_path(self.state, DOMAIN).read_bytes()
        data = self.read()
        profile = data['New Bookmarks'][0]
        self.assertEqual(profile['Option Key Sends'], 2)
        self.assertIs(profile['Allow modifyOtherKeys'], True)
        self.assertEqual(data['Default Bookmark Guid'], profile['Guid'])
        self.run_setup()
        self.assertEqual(macos.state_path(self.state, DOMAIN).read_bytes(), before)
        self.assertEqual(len(self.backups()), 1)
        backup = self.backups()[0]
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        self.assertEqual((backup/'preferences.missing').stat().st_mode & 0o777, 0o600)

    def test_only_default_profile_changes(self):
        original = {'Default Bookmark Guid':'second', 'Unrelated':'preserve', 'New Bookmarks':[
            {'Guid':'first', 'Option Key Sends':1, 'Allow modifyOtherKeys':False},
            {'Guid':'second', 'Right Option Key Sends':1, 'Custom':'preserve'}]}
        self.write(original)
        self.run_setup()
        actual = self.read()
        expected = dict(original)
        expected['New Bookmarks'] = [original['New Bookmarks'][0], dict(original['New Bookmarks'][1], **{'Option Key Sends':2,'Allow modifyOtherKeys':True})]
        self.assertEqual(actual, expected)
        self.assertEqual(original, __import__('plistlib').loads((self.backups()[0]/'preferences.plist').read_bytes()))

    def test_unresolved_default_custom_folder_or_running_app_preserved(self):
        for original, extra in [({'Default Bookmark Guid':'missing','New Bookmarks':[{'Guid':'other'}]}, {}),
                                ({'LoadPrefsFromCustomFolder':True}, {}),
                                ({'Keep':1}, {'ITERM_RUNNING':'0'})]:
            with self.subTest(original=original):
                self.write(original)
                self.env.update(extra)
                self.run_setup(False)
                self.assertEqual(self.read(), original)
                self.assertEqual(self.backups(), [])
                self.env.pop('ITERM_RUNNING', None)

    def test_export_failure_preserves_existing_domain(self):
        original = {'Keep':'private'}
        self.write(original)
        self.env['FAKE_EXPORT'] = DOMAIN
        self.run_setup(False)
        self.assertEqual(self.read(), original)
        self.assertEqual(self.backups(), [])

    def test_failed_import_restores_original_and_retry_succeeds(self):
        original = {'Keep':'private'}
        self.write(original)
        self.env['FAKE_IMPORT_AT'] = DOMAIN+':1'
        self.run_setup(False)
        self.assertEqual(self.read(), original)
        self.env.pop('FAKE_IMPORT_AT')
        self.run_setup()
        self.assertEqual(self.read()['Keep'], 'private')

if __name__ == '__main__': unittest.main()
