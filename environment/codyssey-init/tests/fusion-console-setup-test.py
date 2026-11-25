#!/usr/bin/env python3
"""Exercise the guardrails for console-driven guest authorization."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts/intel-macos-vm"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("console_setup", SCRIPTS / "open-guest-setup.py")
console = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(console)


class ConsoleSetupTests(unittest.TestCase):
    def test_finder_focus_accepts_adjacent_menu_names_read_as_one_label(self):
        labels = [(0.12, 0.02, "Edit"), (0.24, 0.02, "View Window Help")]
        self.assertTrue(console.can_focus_finder(labels))
        self.assertFalse(console.can_focus_finder([labels[0], (0.24, 0.15, "View Window Help")]))

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

    def test_preset_password_requires_opt_in_from_the_console_launcher(self):
        with patch.dict(os.environ, CODYSSEY_FUSION_USE_LAB_PASSWORD="0"):
            self.assertIsNone(console.guest_password())
        with patch.dict(os.environ, CODYSSEY_FUSION_USE_LAB_PASSWORD="1"):
            self.assertEqual(console.guest_password(), "vm user password")

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

    def test_handled_settings_prompt_does_not_hide_guest_readiness(self):
        finder = [
            (0.10, 0.02, "Finder"),
            (0.30, 0.22, "Start Setup.command"),
            (0.50, 0.22, "VMware Tools.pkg"),
        ]
        extension = [
            (0.50, 0.32, "System Extension Blocked"),
            (0.50, 0.37, 'extension(s) signed by "VMware, Inc."'),
            (0.50, 0.50, "Open System Settings"),
        ]
        frames = [(800, 600), finder], [(800, 600), extension]
        with tempfile.TemporaryDirectory() as temporary:
            vmx = Path(temporary) / "base.vmx"
            vmx.with_name("vmware.log").write_text("Started VNC server, listening at 127.0.0.1:49999\n")
            clock = 0

            def slow_guest(_seconds):
                nonlocal clock
                clock += 110

            with (
                patch.object(console, "guest_password", return_value="disposable"),
                patch.object(console, "read_frame", side_effect=[frames[0]] * 2 + [frames[1]] * 4),
                patch.object(console, "console", return_value=MagicMock()),
                patch.object(console, "click") as click,
                patch.object(console.time, "monotonic", side_effect=lambda: clock),
                patch.object(console.time, "sleep", side_effect=slow_guest),
                patch.object(console.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="ready")) as status,
            ):
                console.open_setup("/fake/vmcli", vmx, "/fake/ocr", vmx.with_suffix(".png"), 49999, "vmuser", "1234")
            self.assertEqual([entry.args[-1] for entry in click.call_args_list], [2, 1])
            self.assertEqual(status.call_count, 4)

    def test_vmware_authorization_after_the_extension_prompt_can_omit_the_account_label(self):
        labels = [
            (0.5, 0.40, "Privacy & Security is trying to modify"),
            (0.5, 0.43, "your system settings."),
            (0.5, 0.46, "Enter your password to allow this."),
            (0.5, 0.51, "Password"),
            (0.6, 0.57, "Modify Settings"),
        ]
        self.assertEqual(
            console.approval_target(labels, True, "12ab34cd", "vmuser", {"vmware-extension"}),
            ("vmware-auth", (0.5, 0.51), 1),
        )
        self.assertIsNone(console.approval_target(labels, True, "12ab34cd", "vmuser", set()))
        offset = [(0.20, y, text) for _, y, text in labels[:3]] + labels[3:]
        self.assertIsNone(
            console.approval_target(offset, True, "12ab34cd", "vmuser", {"vmware-extension"})
        )


if __name__ == "__main__":
    unittest.main()
