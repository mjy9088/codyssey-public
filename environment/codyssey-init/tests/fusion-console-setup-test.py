#!/usr/bin/env python3
"""Exercise the guardrails for console-driven guest authorization."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts/intel-macos-vm"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("console_setup", SCRIPTS / "open-guest-setup.py")
console = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(console)


class ConsoleSetupTests(unittest.TestCase):
    def test_password_requires_current_prompt_and_terminal_focus(self):
        prompt = (0.4, 0.3, "Codyssey 12ab34cd password:")
        terminal = (0.1, 0.02, "Terminal")
        target = ("password", None, 0)
        self.assertEqual(console.approval_target([terminal, prompt], True, "12ab34cd", "vmuser", set()), target)
        self.assertIsNone(console.approval_target([prompt], True, "12ab34cd", "vmuser", set()))
        self.assertIsNone(console.approval_target([terminal, prompt], True, "abcdef12", "vmuser", set()))
        self.assertIsNone(console.approval_target([terminal, prompt], True, "12ab34cd", "vmuser", {"password"}))

    def test_only_known_extension_prompts_are_selected(self):
        allow = (0.7, 0.7, "Allow")
        vmware = (0.5, 0.5, "System software from developer “VMware, Inc.” was blocked")
        self.assertEqual(
            console.approval_target([allow, vmware], True, "12ab34cd", "vmuser", set()),
            ("vmware-extension", (0.7, 0.7), 1),
        )
        self.assertIsNone(console.approval_target([allow], True, "12ab34cd", "vmuser", set()))
        unrelated = [(0.7, 0.7, "Agree"), (0.5, 0.5, "License Agreement")]
        self.assertIsNone(console.approval_target(unrelated, True, "12ab34cd", "vmuser", set()))

    def test_completed_terminal_prompt_does_not_hide_extension_dialog(self):
        labels = [
            (0.1, 0.02, "Terminal"),
            (0.2, 0.2, "Codyssey 12ab34cd password:"),
            (0.5, 0.32, "System Extension Blocked"),
            (0.5, 0.37, 'extension(s) signed by "VMware, Inc."'),
            (0.5, 0.50, "Open System Settings"),
        ]
        self.assertEqual(
            console.approval_target(labels, True, "12ab34cd", "vmuser", {"password"}),
            ("vmware-settings", (0.5, 0.50), 1),
        )

    def test_guest_credential_requires_a_private_regular_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            password_file = Path(temporary) / "guest-password"
            password_file.write_text("synthetic-password\n")
            with patch.dict(os.environ, CODYSSEY_FUSION_GUEST_PASSWORD_FILE=str(password_file)):
                password_file.chmod(0o644)
                with self.assertRaises(ValueError):
                    console.guest_password()
                password_file.chmod(0o600)
                self.assertEqual(console.guest_password(), "synthetic-password")
                password_file.write_text("synthetic\nsecond-line\n")
                with self.assertRaises(ValueError):
                    console.guest_password()

    def test_terminal_prompt_selects_its_allow_button_over_settings_background(self):
        labels = [
            (0.50, 0.28, '"Terminal" would like to'),
            (0.50, 0.30, "administer your computer."),
            (0.56, 0.41, "Allow"),
            (0.80, 0.74, "Allow"),
        ]
        self.assertEqual(
            console.approval_target(labels, True, "12ab34cd", "vmuser", set()),
            ("terminal-admin", (0.56, 0.41), 1),
        )


if __name__ == "__main__":
    unittest.main()
