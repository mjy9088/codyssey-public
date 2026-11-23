#!/usr/bin/env python3
"""Test install and verification console rules with synthetic OCR labels."""

import importlib.util
import io
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts/intel-macos-vm"
sys.path.insert(0, str(SCRIPTS))

def load_script(filename):
    script = SCRIPTS / filename
    spec = importlib.util.spec_from_file_location(script.stem, script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


installer = load_script("install-guest.py")
workstation = load_script("watch-workstation-console.py")
input_driver = load_script("drive-workstation-input.py")


class InstallerScreenTests(unittest.TestCase):
    def test_language_selection_is_bound_to_the_recovery_picker(self):
        labels = [(0.5, 0.36, "Language"), (0.5, 0.43, "English")]
        self.assertEqual(installer.installer_action(labels), ("language", (0.5, 0.43), 1))
        self.assertIsNone(installer.installer_action(labels[1:]))

    def test_license_confirmation_distinguishes_the_foreground_button(self):
        labels = [
            (0.50, 0.49, "I have read and agree to the"),
            (0.50, 0.52, "terms of the software license agreement."),
            (0.56, 0.58, "Agree"),
            (0.56, 0.83, "Agree"),
        ]
        self.assertEqual(installer.installer_action(labels), ("license", (0.56, 0.58), 1))

    def test_target_requires_the_install_selection_and_named_volume(self):
        labels = [
            (0.5, 0.33, "Select the disk where you want to install macOS."),
            (0.5, 0.50, "Macintosh HD"),
            (0.7, 0.72, "Continue"),
        ]
        self.assertEqual(
            installer.installer_action(labels),
            (("disk", (0.5, 0.50), 1), ("install", (0.7, 0.72), 1)),
        )
        self.assertIsNone(installer.installer_action(labels[1:]))

    def test_account_requires_all_expected_fields_in_order(self):
        labels = [
            (0.5, 0.22, "Create a Mac Account"),
            (0.27, 0.38, "Full name:"),
            (0.32, 0.49, "Password: new password"),
            (0.54, 0.49, "verify"),
            (0.7, 0.82, "Continue"),
        ]
        self.assertEqual(
            installer.setup_action(labels, False),
            ("account-fields", ((0.46, 0.38), (0.40, 0.49), (0.63, 0.49)), 1),
        )
        self.assertIsNone(installer.setup_action(labels[:-2], False))

    def test_country_search_only_focuses_the_country_list(self):
        labels = [
            (0.5, 0.36, "Select Your Country or Region"),
            (0.4, 0.45, "Afghanistan"),
            (0.84, 0.85, "Continue"),
        ]
        self.assertEqual(installer.setup_action(labels, False), ("find-region", (0.4, 0.45), 1))
        self.assertIsNone(installer.setup_action(labels[1:], False))

    def test_new_mac_option_is_selected_before_continuing(self):
        labels = [
            (0.5, 0.36, "Transfer Your Data to This Mac"),
            (0.4, 0.67, "• Set up as new"),
            (0.84, 0.85, "Continue"),
        ]
        self.assertEqual(
            installer.setup_action(labels, False),
            ("new-mac", ((0.4, 0.67), (0.84, 0.85)), 1),
        )

    def test_shutdown_requires_complete_inventory_and_resolves_aliases(self):
        with tempfile.TemporaryDirectory() as temporary:
            vmx = Path(temporary) / "Guest.vmx"
            vmx.touch()
            alias = vmx.with_name("Guest Alias.vmx")
            alias.symlink_to(vmx)
            self.assertFalse(installer.guest_has_stopped("Total running VMs: 1\n", vmx))
            self.assertFalse(installer.guest_has_stopped(f"Total running VMs: 1\n{alias}\n", vmx))
            self.assertTrue(installer.guest_has_stopped("Total running VMs: 0\n", vmx))

    def test_apple_account_confirmation_takes_priority_over_the_background(self):
        labels = [
            (0.50, 0.47, "Are you sure you want to skip"),
            (0.50, 0.50, "signing in with an Apple"),
            (0.50, 0.52, "Account?"),
            (0.44, 0.63, "Don't Skip"),
            (0.56, 0.64, "Skip"),
            (0.17, 0.86, "Set Up Later"),
        ]
        self.assertEqual(installer.setup_action(labels, True),
                         ("apple-account-confirmation", (0.56, 0.64), 1))
        self.assertIsNone(installer.setup_action(labels[:4] + labels[5:], True))

    def test_widget_reopen_alert_is_declined_before_the_apple_account_prompt(self):
        apple_account = [
            (0.48, 0.75, "This Mac will be associated with your Apple Account"),
            (0.44, 0.63, "Don't Skip"),
            (0.56, 0.64, "Skip"),
        ]
        widget = [
            (0.55, 0.40, "from previously opened versions."),
            (0.55, 0.42, "Are you sure you want to open it?"),
            (0.50, 0.54, "Don't Open"),
            (0.62, 0.54, "Open Anyway"),
        ]
        self.assertEqual(installer.setup_action(widget + apple_account, True),
                         ("decline-app-reopen", (0.50, 0.54), 1))
        widget[0] = (0.55, 0.40, "reviously opened versions.")
        self.assertEqual(installer.setup_action(widget + apple_account, True),
                         ("decline-app-reopen", (0.50, 0.54), 1))
        self.assertEqual(installer.setup_action(apple_account, True),
                         ("apple-account-confirmation", (0.56, 0.64), 1))

    def test_reopen_decline_uses_the_centered_alert_when_vision_misses_left_button(self):
        labels = [
            (0.50, 0.30, "from previously opened versions."),
            (0.50, 0.32, "Are you sure you want to open it?"),
            (0.56, 0.46, "Open Anyway"),
        ]
        action, point, count = installer.setup_action(labels, True)
        self.assertEqual((action, count), ("decline-app-reopen", 1))
        self.assertAlmostEqual(point[0], 0.44)
        self.assertAlmostEqual(point[1], 0.46)
        self.assertIsNone(installer.setup_action(labels[:1] + labels[2:], True))


class WorkstationScreenTests(unittest.TestCase):
    def test_sequoia_names_the_swift_helper_in_the_input_source_prompt(self):
        labels = [
            (0.50, 0.46, 'Allow "swift-frontend" to enable'),
            (0.50, 0.50, "The developer of the input source will be"),
            (0.44, 0.64, "Don't Allow"),
            (0.57, 0.64, "Allow"),
        ]
        self.assertEqual(workstation.action_for(labels, "vmuser", True),
                         ("gureum", (0.57, 0.64), 1))
        self.assertIsNone(workstation.action_for(labels[1:], "vmuser", True))
        self.assertIsNone(workstation.action_for(labels[:1] + labels[2:], "vmuser", True))
        self.assertIsNone(workstation.action_for(labels[:-1] + [(0.57, 0.78, "Allow")], "vmuser", True))
        ocr_labels = labels[:1] + [
            (0.50, 0.49, "The developer if the input source will be"),
            (0.50, 0.51, "able to access anything you type with"),
        ] + labels[2:]
        self.assertEqual(workstation.action_for(ocr_labels, "vmuser", True),
                         ("gureum", (0.57, 0.64), 1))

    def test_typing_relays_ordered_checkpoints_only_after_console_confirmation(self):
        transcript = b"Verified shortcuts.\n" + b"".join(
            b"Codyssey typing " + bytes([letter]) + b"\r\n" for letter in b"ABCDE"
        )
        with tempfile.TemporaryDirectory() as temporary:
            vmx = Path(temporary) / "guest.vmx"
            vmx.with_name("vmware.log").write_text("Started VNC server, listening at 127.0.0.1:49999\n")
            output = io.BytesIO()
            with (
                patch.object(input_driver, "console", return_value=MagicMock()) as open_console,
                patch.object(input_driver, "send_typing") as send,
            ):
                input_driver.relay(io.BytesIO(transcript), output, vmx, 49999)
                self.assertEqual(output.getvalue(), transcript)
                self.assertEqual([call.args[-1] for call in send.call_args_list], ["gks ", None, "abc", None, "gks "])
                self.assertEqual(open_console.call_count, 5)
                send.reset_mock()
                with self.assertRaisesRegex(RuntimeError, "Unexpected"):
                    input_driver.relay(io.BytesIO(b"Codyssey typing D\n"), io.BytesIO(), vmx, 49999)
                with self.assertRaisesRegex(RuntimeError, "loopback"):
                    input_driver.relay(io.BytesIO(b"Codyssey typing A\n"), io.BytesIO(), vmx, 49998)
                with self.assertRaisesRegex(RuntimeError, "before completing"):
                    input_driver.relay(io.BytesIO(b"Guest timeout\n"), io.BytesIO(), vmx, 49999)
                send.assert_not_called()

    def test_input_switch_sends_a_control_space_chord(self):
        connection = Mock()
        input_driver.send_typing(connection, None)
        events = [struct.unpack(">BBHI", call.args[0]) for call in connection.sendall.call_args_list]
        self.assertEqual(events, [(4, 1, 0, 0xffe3), (4, 1, 0, 32), (4, 0, 0, 32), (4, 0, 0, 0xffe3)])

    def test_ambient_text_cannot_approve_an_unrelated_dialog(self):
        labels = [
            (0.45, 0.06, "Gureum Help"),
            (0.45, 0.08, "Input Sources"),
            (0.50, 0.46, "Terminal would like to administer your computer"),
            (0.57, 0.64, "Allow"),
        ]
        self.assertIsNone(workstation.action_for(labels, "vmuser", True))


if __name__ == "__main__":
    unittest.main()
