#!/usr/bin/env python3
"""Exercise ownership, cleanup, payload isolation, and guest failure propagation."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE_TART = r'''
import json, os, sys, tarfile, time
args = sys.argv[1:]
if args == ["--version"]:
    print("synthetic-tart-version")
    sys.exit(0)
with open(os.environ["VM_TEST_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\n")
scenario = os.environ.get("VM_TEST_SCENARIO", "success")
if args[0] == "clone" and scenario == "collision":
    sys.exit(1)
if args[0] == "set" and scenario == "set-failure":
    sys.exit(1)
if args[0] == "run":
    if scenario == "boot-failure":
        sys.exit(1)
    time.sleep(60)
if args[0] == "exec":
    if scenario == "boot-failure":
        sys.exit(1)
    if "-i" in args:
        with tarfile.open(fileobj=sys.stdin.buffer, mode="r|*") as archive:
            names = [item.name for item in archive]
        with open(os.environ["VM_TEST_PAYLOAD"], "w") as stream:
            json.dump(names, stream)
    elif "-c" in args:
        print("/Users/synthetic/guest work")
    elif any("prepare-macos-vm.sh" in item for item in args) and scenario == "prepare-failure":
        sys.exit(17)
    elif any("verify-macos-vm.sh" in item for item in args) and scenario == "verify-failure":
        sys.exit(19)
    elif "/opt/homebrew/bin/colima" in args and scenario == "shutdown-failure":
        sys.exit(23)
'''


class OrchestrationTests(unittest.TestCase):
    def run_case(self, scenario="success", extra=()):
        with tempfile.TemporaryDirectory(prefix="vm-orchestration-") as directory:
            work = Path(directory)
            fakebin = work / "bin"
            fakebin.mkdir()
            for name, script in {
                "uname": '#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo arm64;; esac\n',
                "sw_vers": "#!/bin/sh\necho 15.0\n",
                "mise": '#!/bin/sh\n[ "$1" = exec ] && [ "$2" = -- ] || exit 1\nshift 2\nexec "$@"\n',
                "tart": "#!" + sys.executable + "\n" + FAKE_TART,
            }.items():
                target = fakebin / name
                target.write_text(script)
                target.chmod(0o755)
            log = work / "commands.jsonl"
            payload = work / "payload.json"
            env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"],
                       VM_TEST_LOG=str(log), VM_TEST_PAYLOAD=str(payload),
                       VM_TEST_SCENARIO=scenario, TS_AUTHKEY="synthetic-secret-must-not-transfer")
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/create-macos-vm.sh"),
                 "--image", "reviewed-base", "--name", "synthetic-test", *extra],
                env=env, text=True, capture_output=True, timeout=25,
            )
            commands = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            names = json.loads(payload.read_text()) if payload.exists() else []
            return result, commands, names

    def test_success_keeps_stopped_vm_and_transfers_only_environment(self):
        result, commands, names = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["stop", "synthetic-test"], commands)
        shutdown = ["exec", "synthetic-test", "/opt/homebrew/bin/colima", "stop", "--profile", "codyssey-verify"]
        self.assertLess(commands.index(shutdown), commands.index(["stop", "synthetic-test"]))
        self.assertFalse(any(cmd[0] == "delete" for cmd in commands))
        self.assertIn("init.sh", names)
        self.assertIn("verify-macos-setup.py", names)
        self.assertNotIn(".env", names)
        self.assertNotIn("gost/gost.yaml", names)
        self.assertTrue(all(not name.startswith(("coursework/", "archive/")) for name in names))
        self.assertNotIn("synthetic-secret-must-not-transfer", json.dumps(commands))
        self.assertTrue(any("DOCKER_CONTEXT=colima-codyssey-verify" in cmd for cmd in commands))
        self.assertTrue(any("/Users/synthetic/guest work/scripts/verify-macos-vm.sh" in cmd for cmd in commands))

    def test_success_can_delete_owned_vm(self):
        result, commands, _ = self.run_case(extra=("--delete-on-success",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["delete", "synthetic-test"], commands)

    def test_collision_never_stops_or_deletes_existing_vm(self):
        result, commands, _ = self.run_case("collision", ("--delete-on-success",))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [["clone", "reviewed-base", "synthetic-test"]])

    def test_failures_are_propagated_and_retained(self):
        for scenario, code in (("set-failure", 1), ("boot-failure", 1), ("prepare-failure", 17), ("verify-failure", 19), ("shutdown-failure", 1)):
            with self.subTest(scenario=scenario):
                result, commands, _ = self.run_case(scenario, ("--delete-on-success",))
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertIn(["stop", "synthetic-test"], commands)
                self.assertFalse(any(cmd[0] == "delete" for cmd in commands))
                if scenario == "prepare-failure":
                    self.assertFalse(any(any("verify-macos-vm.sh" in arg for arg in cmd) for cmd in commands))

    def test_mutable_remote_image_is_rejected_before_creation(self):
        result, commands, _ = self.run_case(extra=("--image", "ghcr.io/example/macos:latest",))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [])

    def test_pinned_remote_image_is_accepted(self):
        image = "ghcr.io/example/macos@sha256:" + "a" * 64
        result, commands, _ = self.run_case(extra=("--image", image,))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands[0], ["clone", image, "synthetic-test"])

    def test_invalid_name_is_rejected_before_creation(self):
        result, commands, _ = self.run_case(extra=("--name", "../existing",))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [])

    def test_help_never_provisions(self):
        for script in ("create-macos-vm.sh", "prepare-macos-vm.sh", "verify-macos-vm.sh"):
            result = subprocess.run(["bash", str(ROOT / "scripts" / script), "--help"],
                                    text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            self.assertIn("Usage:", result.stdout)


if __name__ == "__main__":
    unittest.main()
