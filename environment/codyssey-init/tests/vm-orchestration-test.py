#!/usr/bin/env python3
"""Exercise ownership, cleanup, payload isolation, and guest failure propagation."""
import io
import json
import os
from pathlib import Path
import plistlib
import runpy
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
from types import ModuleType
import unittest
from unittest import mock

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
    with open(os.environ["VM_TEST_TART_PID"], "w") as stream:
        stream.write(str(os.getpid()))
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
    elif args[-1] == "/usr/bin/true" and scenario == "delayed-readiness":
        marker = os.environ["VM_TEST_READY"]
        count = int(open(marker).read()) + 1 if os.path.exists(marker) else 1
        open(marker, "w").write(str(count))
        if count < 3:
            sys.exit(1)
    elif any("check-preinstalled-apps.py" in item for item in args) and scenario == "preflight-failure":
        sys.exit(21)
    elif "--stop" in args:
        if scenario in ("shutdown-failure", "verify-shutdown-failure"):
            sys.exit(23)
    elif any("prepare-macos-vm.sh" in item for item in args):
        if scenario == "prepare-failure": sys.exit(17)
        if scenario == "prepare-interrupt": sys.exit(130)
        if scenario == "prepare-terminate": sys.exit(143)
    elif any("verify-macos-vm.sh" in item for item in args) and scenario in ("verify-failure", "verify-shutdown-failure", "verify-stop-failure"):
        sys.exit(19)
if args[0] == "stop" and scenario in ("stop-failure", "verify-stop-failure"):
    sys.exit(29)
if args[0] == "stop":
    print("TART_STOP_COMPLETE")
'''


FAKE_VMRUN = r'''
import json, os, pathlib, sys
assert sys.argv[1:3] == ["-T", "fusion"]
command, *args = sys.argv[3:]
with open(os.environ["VM_TEST_LOG"], "a") as stream:
    stream.write(json.dumps([command, *args]) + "\n")
running = pathlib.Path(os.environ["VM_TEST_RUNNING"])
scenario = os.environ["VM_TEST_SCENARIO"]
if command == "list":
    stopping = running.with_suffix(".stopping")
    if stopping.exists() and scenario == "shutdown-inventory-failure":
        sys.exit(30)
    print("Total running VMs:", int(running.exists()))
    if running.exists():
        print(running.read_text())
        if stopping.exists():
            running.unlink()
elif command == "clone":
    assert pathlib.Path(args[1]).parent.is_dir()
    assert args[2:] == ["full", "-cloneName=" + pathlib.Path(args[1]).stem]
    pathlib.Path(args[1]).touch()
elif command == "start":
    assert args[1:] == (["nogui"] if os.environ.get("VM_TEST_QUICK") == "1" else ["gui"])
    running.write_text(args[0])
elif command == "getGuestIPAddress":
    assert len(args) == 1 and pathlib.Path(args[0]).samefile(running.read_text())
    if scenario == "quick-prep-no-address":
        sys.exit(1)
    print("192.0.2.42")
elif command == "readVariable":
    assert args[1:] == ["guestVar", "codyssey.ssh-host-key"]
    assert pathlib.Path(args[0]).samefile(running.read_text())
    if scenario == "quick-prep-invalid-key":
        print("ssh-rsa INVALIDKEY")
    elif scenario != "quick-prep-no-key":
        print("ssh-ed25519 GUESTKEY")
elif command == "stop":
    assert args[1:] == ["soft"]
    if scenario == "stop-failure":
        sys.exit(29)
    if scenario in ("delayed-shutdown", "shutdown-inventory-failure"):
        running.with_suffix(".stopping").touch()
    else:
        running.unlink()
elif command == "deleteVM":
    assert not running.exists()
    pathlib.Path(args[0]).unlink()
else:
    sys.exit(98)
'''

FAKE_VMCLI = r'''
import json, os, pathlib, sys
vmx, module, action, key, value = sys.argv[1:]
assert module == "ConfigParams" and action == "SetEntry"
assert pathlib.Path(vmx).is_file()
assert not pathlib.Path(os.environ["VM_TEST_RUNNING"]).exists()
with open(os.environ["VM_TEST_LOG"], "a") as stream:
    stream.write(json.dumps(["configure", vmx, key, value]) + "\n")
if os.environ["VM_TEST_SCENARIO"] == "offline-configuration-failure" and key == "sharedFolder.maxNum":
    sys.exit(38)
'''


FAKE_SSH = r'''
import json, os, shlex, sys, tarfile
options = sys.argv[1:-2]
assert "StrictHostKeyChecking=yes" in options
assert "HostKeyAlias=codyssey-fusion" in options
assert 'UserKnownHostsFile="' + os.environ["CODYSSEY_FUSION_KNOWN_HOSTS"] + '"' in options
assert sys.argv[-2] == "192.0.2.42"
args = shlex.split(sys.argv[-1])
with open(os.environ["VM_TEST_LOG"], "a") as stream:
    stream.write(json.dumps(["ssh", *args]) + "\n")
scenario = os.environ["VM_TEST_SCENARIO"]
if scenario == "quick-prepare":
    pin = open(os.environ["CODYSSEY_FUSION_KNOWN_HOSTS"]).read()
    assert pin == "codyssey-fusion ssh-ed25519 GUESTKEY\n"
if scenario == "quick-prep-mismatch":
    sys.exit(255)
if scenario == "quick-prep-console" and args[:2] == ["/bin/sh", "-c"]:
    sys.exit(1)
if scenario == "quick-prep-clt" and args == ["/usr/bin/xcode-select", "-p"]:
    sys.exit(1)
if "--managed" in args and scenario in ("lost-prepare-reply", "unresolved-guest-stop"):
    sys.exit(255)
if "--stop" in args and scenario == "unresolved-guest-stop":
    print("Guest Colima preparation is still running.", file=sys.stderr)
    sys.exit(1)
if args[:2] == ["/bin/sh", "-c"]:
    if args[2].startswith("mktemp"):
        print("/Users/synthetic/guest's work")
elif args[0] == "/usr/bin/mktemp":
    print("/tmp/codyssey-fusion-base.Abc123")
elif args[0] == "/usr/bin/tar":
    expected = "/tmp/codyssey-fusion-base.Abc123" if scenario == "quick-prepare" else "/Users/synthetic/guest's work"
    assert args[1:] == ["-xf", "-", "-C", expected]
    with tarfile.open(fileobj=sys.stdin.buffer, mode="r|*") as archive:
        names = [item.name for item in archive]
    with open(os.environ["VM_TEST_PAYLOAD"], "w") as stream:
        json.dump(names, stream)
elif len(args) > 1 and args[1].endswith("/prepare-fusion-base.sh"):
    if os.environ.get("CODYSSEY_FUSION_UNATTENDED") == "1" and os.environ["CODYSSEY_FUSION_GUEST_USER"] == "vmuser":
        assert "-T" in options and args[2:] == ["--sudo-password-stdin"]
        assert sys.stdin.read() == "vm user password\n"
    else:
        assert "-t" in options and args[2:] == []
elif len(args) > 1 and args[1].endswith("/vm-aqua-exec.py"):
    scenario = os.environ["VM_TEST_SCENARIO"]
    if scenario == "verify-failure":
        sys.exit(19)
'''


class OrchestrationTests(unittest.TestCase):
    def test_fusion_stop_request_times_out_and_reaps_unresponsive_vmrun(self):
        with tempfile.TemporaryDirectory() as temporary:
            vmrun = Path(temporary) / "vmrun"
            vmrun.write_text(
                f"#!{sys.executable}\n"
                "import os, sys, time\n"
                "assert sys.argv[1:] == ['-T', 'fusion', 'stop', 'test VM.vmx', 'soft']\n"
                "print(os.getpid(), flush=True)\n"
                "time.sleep(30)\n"
            )
            vmrun.chmod(0o755)
            result = subprocess.run(
                ["bash", "-c", '. "$1"; fusion_vmrun=$2; fusion_request_stop "test VM.vmx" soft 1',
                 "test-fusion-stop", str(ROOT / "scripts/vm-fusion.sh"), str(vmrun)],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10,
            )
            self.assertNotEqual(result.returncode, 0, result.stderr)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(result.stdout), 0)

    @unittest.skipUnless(shutil.which("ssh-keygen"), "OpenSSH is required")
    def test_unattended_guest_key_is_usable_without_terminal_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            identity = Path(temporary) / "credentials" / "id_ed25519"
            result = subprocess.run(
                ["bash", "-c", '. "$1"; fusion_ensure_guest_identity "$2"',
                 "test-fusion-key", str(ROOT / "scripts/vm-fusion.sh"), str(identity)],
                env=dict(os.environ, CODYSSEY_FUSION_UNATTENDED="1"),
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(identity.stat().st_mode & 0o777, 0o600)
            public_key = subprocess.run(
                ["ssh-keygen", "-y", "-f", str(identity)],
                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                check=True, timeout=10,
            )
            self.assertEqual(public_key.stdout, identity.with_suffix(".pub").read_text())

    def run_case(self, scenario="success", extra=(), arch="arm64", quick=False, unattended_guest=None):
        with tempfile.TemporaryDirectory(prefix="vm-orchestration-") as directory:
            work = Path(directory)
            fakebin = work / "bin"
            fakebin.mkdir()
            for name, script in {
                "uname": '#!/bin/sh\ncase "$1" in -s) echo "${VM_TEST_PLATFORM:-Darwin}";; -m) echo "$VM_TEST_ARCH";; esac\n',
                "sw_vers": "#!/bin/sh\necho 15.0\n",
                "mise": '''#!/bin/sh
printf '%s\\n' "$*" >> "$VM_MISE_LOG"
[ "$1" = -C ] && [ "$2" = "$VM_TOOL_ROOT" ] && [ "$3" = -E ] && [ "$4" = vm ] || exit 97
shift 4
if [ "$*" = 'install tart' ]; then
  [ "$VM_TEST_SCENARIO" != install-failure ] || exit 37
  exit 0
fi
[ "$1" = exec ] && [ "$2" = tart ] && [ "$3" = -- ] && [ "$4" = tart ] || exit 97
shift 4
exec tart "$@"
''',
                "tart": "#!" + sys.executable + "\n" + FAKE_TART,
                "vmrun": "#!" + sys.executable + "\n" + FAKE_VMRUN,
                "vmcli": "#!" + sys.executable + "\n" + FAKE_VMCLI,
                "ssh": "#!" + sys.executable + "\n" + FAKE_SSH,
                "ssh-agent": '#!/bin/sh\nexport SSH_AGENT_PID=123\nexec "$@"\n',
                "ssh-add": '#!/bin/sh\nexit 0\n',
                "ssh-keygen": '#!/bin/sh\n[ "$1" = -lf ]\n',
                "shasum": '#!/bin/sh\ncat >/dev/null\necho "synthetic-hash  -"\n',
            }.items():
                target = fakebin / name
                target.write_text(script)
                target.chmod(0o755)
            log = work / "commands.jsonl"
            payload = work / "payload.json"
            ready = work / "ready-count"
            tart_pid = work / "tart.pid"
            env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"],
                        TMPDIR=str(work), VM_TEST_TART_PID=str(tart_pid), VM_TEST_LOG=str(log), VM_TEST_PAYLOAD=str(payload),
                        VM_MISE_LOG=str(work / "mise.log"), VM_TOOL_ROOT=str(ROOT),
                        VM_TEST_READY=str(ready), VM_TEST_SCENARIO=scenario,
                        VM_TEST_PLATFORM="Linux" if scenario == "linux" else "Darwin",
                        TS_AUTHKEY="synthetic-secret-must-not-transfer")
            base = work / "base VM.vmx"
            base.touch()
            known_hosts = work / "known hosts"
            known_hosts.write_text("codyssey-fusion synthetic-key\n")
            if arch == "x86_64":
                env.update(CODYSSEY_FUSION_VMRUN=str(fakebin / "vmrun"),
                           CODYSSEY_FUSION_GUEST_USER="synthetic",
                           CODYSSEY_FUSION_KNOWN_HOSTS=str(known_hosts),
                           VM_TEST_RUNNING=str(work / "running"))
                if scenario == "collision":
                    (work / "synthetic-test.vmwarevm").mkdir()
                if scenario == "offline-configuration-failure":
                    env["fusion_isolated"] = "1"
            env["VM_TEST_ARCH"] = arch
            command = ["bash", str(ROOT / "scripts/create-macos-vm.sh"),
                       "--image", str(base) if arch == "x86_64" else "reviewed-base",
                       "--name", "synthetic-test", *extra]
            if quick:
                env["VM_TEST_QUICK"] = "1"
                command = ["bash", str(ROOT / "scripts/verify-intel-macos.sh"), str(base), *extra]
                identity = work / "lab-key"
                identity.touch()
                env.update(CODYSSEY_FUSION_STORAGE=str(work / "storage"),
                           CODYSSEY_FUSION_CREDENTIALS=str(work / "credentials"),
                           CODYSSEY_FUSION_IDENTITY=str(identity))
                env.pop("codyssey_fusion_agent_pid", None)
                env.pop("CODYSSEY_FUSION_UNATTENDED", None)
                if unattended_guest is not None:
                    env.update(CODYSSEY_FUSION_UNATTENDED="1", CODYSSEY_FUSION_GUEST_USER=unattended_guest)
                if "--prepare" in extra:
                    known_hosts.unlink()
                    Path(env["VM_TEST_RUNNING"]).write_text(str(base))
                    env["CODYSSEY_FUSION_PREPARE_TIMEOUT"] = "1"
            result = subprocess.run(
                command, cwd=work, env=env, stdin=subprocess.DEVNULL, text=True, capture_output=True, timeout=25,
            )
            if quick and "--prepare" in extra:
                self.assertEqual(known_hosts.exists(), scenario == "quick-prepare")
            elif quick:
                logs = list((work / "storage/runs").glob("*/verify.log"))
                self.assertEqual(len(logs), 1)
                self.assertIn("fresh macOS VM", logs[0].read_text())
            mise_calls = (work / "mise.log").read_text().splitlines() if (work / "mise.log").exists() else []
            if scenario == "linux" or arch == "x86_64":
                self.assertEqual(mise_calls, [])
            elif mise_calls:
                self.assertTrue(mise_calls[0].endswith("-E vm install tart"))
                self.assertEqual(sum(line.endswith("install tart") for line in mise_calls), 1)
            else:
                self.assertNotEqual(result.returncode, 0)
            commands = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            names = json.loads(payload.read_text()) if payload.exists() else []
            if tart_pid.exists() and not any(cmd[0] == "stop" for cmd in commands):
                # A retained fake runner would otherwise outlive the fixture.
                try:
                    os.kill(int(tart_pid.read_text()), signal.SIGTERM)
                except ProcessLookupError:
                    pass
            return result, commands, names

    def test_success_keeps_stopped_vm_and_transfers_only_environment(self):
        result, commands, names = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["stop", "synthetic-test"], commands)
        shutdown = ["exec", "synthetic-test", "/bin/bash", "/Users/synthetic/guest work/scripts/prepare-macos-vm.sh", "--disposable", "--stop"]
        self.assertLess(commands.index(shutdown), commands.index(["stop", "synthetic-test"]))
        self.assertFalse(any(cmd[0] == "delete" for cmd in commands))
        self.assertIn("init.sh", names)
        self.assertIn("verify-macos-setup.py", names)
        # The guest must have every input needed to build its isolated check image.
        self.assertIn("tests/managed-j-runtime.sh", names)
        self.assertIn("mise.vm.toml", names)
        self.assertNotIn(".env", names)
        self.assertNotIn("gost/gost.yaml", names)
        self.assertTrue(all(not name.startswith(("coursework/", "archive/")) for name in names))
        self.assertNotIn("synthetic-secret-must-not-transfer", json.dumps(commands))
        self.assertTrue(any("DOCKER_CONTEXT=colima-codyssey-verify" in cmd for cmd in commands))
        self.assertTrue(any("/Users/synthetic/guest work/scripts/verify-macos-vm.sh" in cmd for cmd in commands))
        self.assertLess(result.stdout.index("TART_STOP_COMPLETE"), result.stdout.index("PASS:"))

    def test_intel_workstation_verifies_and_shuts_down_without_docker(self):
        result, commands, _ = self.run_case(arch="x86_64", extra=("--workstation",))
        self.assertEqual(result.returncode, 0, result.stderr)
        verification = next(index for index, cmd in enumerate(commands) if cmd[-1] == "--workstation")
        shutdown = next(index for index, cmd in enumerate(commands) if cmd[0] == "stop")
        self.assertLess(verification, shutdown)
        self.assertFalse(any("prepare-macos-vm.sh" in arg or "DOCKER_CONTEXT" in arg
                             for cmd in commands for arg in cmd))

    def test_fusion_typing_relay_preserves_guest_failure_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            driver = root / "scripts/intel-macos-vm/drive-workstation-input.py"
            driver.parent.mkdir(parents=True)
            driver.write_text('import os; raise SystemExit(int(os.environ["TEST_RELAY"]))\n')
            shell = r"""
set -euo pipefail
. "$1"
fusion_console_enabled=1
fusion_project_root=$2
fusion_vmx=guest.vmx
fusion_console_port=49999
vm_exec() { return "$TEST_GUEST"; }
vm_desktop_exec /fake/guest 1200 bash verifier --workstation
"""
            for guest, relay, expected in ((17, 1, 17), (17, 0, 17), (141, 1, 1), (0, 1, 1), (0, 0, 0)):
                with self.subTest(guest=guest, relay=relay):
                    result = subprocess.run(
                        ["bash", "-c", shell, "fusion-relay", str(ROOT / "scripts/vm-fusion.sh"), str(root)],
                        env=dict(os.environ, TEST_GUEST=str(guest), TEST_RELAY=str(relay)),
                        capture_output=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, expected, result.stderr)

    def test_intel_quick_start_reuses_credentials_and_writes_log(self):
        result, commands, _ = self.run_case(arch="x86_64", quick=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(cmd[-1] == "--workstation" for cmd in commands))
        self.assertEqual([cmd[-1] for cmd in commands if cmd[0] == "start"], ["nogui"])
        self.assertFalse(any("prepare-macos-vm.sh" in arg for cmd in commands for arg in cmd))

    def test_intel_headless_nat_address_uses_current_lease_for_clone_mac(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            vmx, leases = work / "guest.vmx", work / "leases"
            nat = 'ethernet0.connectionType = "nat"\n'
            mac = "00:0c:29:11:22:33"
            config = f'ethernet0.generatedAddress = "{mac}"\n'
            lease = (
                "lease 192.0.2.42 {\n"
                "  ends 0 2099/01/01 00:00:00;\n"
                f"  hardware ethernet {mac};\n"
                "}\n"
            )
            command = [
                "bash", "-c", '. "$1"; fusion_nat_guest_address "$2" "$3"',
                "nat-lease", str(ROOT / "scripts/vm-fusion.sh"), str(vmx), str(leases),
            ]
            for vmx_text, lease_text, expected in (
                (nat + config, lease, "192.0.2.42"),
                (nat + config, lease + lease.replace(mac, "00:0c:29:22:33:44"), ""),
                (nat + config, lease.replace("2099", "2000"), ""),
                (nat.replace("nat", "bridged") + config, lease, ""),
            ):
                vmx.write_text(vmx_text)
                leases.write_text(lease_text)
                result = subprocess.run(command, text=True, capture_output=True, timeout=10)
                self.assertEqual(result.stdout.strip(), expected)
                self.assertEqual(result.returncode, 0 if expected else 1, result.stderr)

    def test_intel_numbered_steps_remember_a_base_when_storage_moves(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary).resolve()
            storage = work / "external storage"
            stored_base = storage / "bases" / "Base.vmwarevm" / "Base.vmx"
            stored_base.parent.mkdir(parents=True)
            stored_base.touch()
            external_base = work / "Other.vmx"
            external_base.touch()
            installer = storage / "Sequoia.iso"
            installer.write_text("synthetic installer\n")
            script = """
set -euo pipefail
. "$1"
export HOME="$5"
unset CODYSSEY_FUSION_STORAGE
fusion_select_storage "$2"
test "$(fusion_storage_path)" = "$2"
fusion_remember_media "$6"
test "$(cat "$2/current-installer")" = "Sequoia.iso"
test "$(fusion_selected_media)" = "$6"
fusion_remember_base "$3"
test "$(cat "$2/current-base")" = "bases/Base.vmwarevm/Base.vmx"
test "$(fusion_selected_base)" = "$3"
mv "$2" "$2-moved"
fusion_select_storage "$2-moved"
test "$(fusion_selected_media)" = "$2-moved/Sequoia.iso"
test "$(CODYSSEY_FUSION_STORAGE="$2" fusion_storage_path)" = "$2"
test "$(fusion_selected_base)" = "$2-moved/bases/Base.vmwarevm/Base.vmx"
test "$(fusion_selected_base "$4")" = "$4"
fusion_remember_base "$4"
test "$(fusion_selected_base)" = "$4"
"""
            result = subprocess.run(
                ["bash", "-c", script, "fusion-selection", str(ROOT / "scripts/vm-fusion.sh"),
                 str(storage), str(stored_base), str(external_base), str(work / "home"), str(installer)],
                text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_unattended_base_preparation_supplies_the_preset_without_a_password_file(self):
        result, commands, _ = self.run_case(
            "quick-prepare", ("--prepare",), arch="x86_64", quick=True, unattended_guest="vmuser",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("--sudo-password-stdin" in command for command in commands))
        self.assertNotIn(["ssh", "/usr/bin/xcode-select", "-p"], commands)

    def test_unattended_flag_does_not_send_the_preset_for_a_custom_account(self):
        result, commands, _ = self.run_case(
            "quick-prepare", ("--prepare",), arch="x86_64", quick=True, unattended_guest="synthetic",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any("--sudo-password-stdin" in command for command in commands))
        self.assertIn(["ssh", "/usr/bin/xcode-select", "-p"], commands)

    def test_intel_base_preparation_pins_only_verified_keys(self):
        cases = {
            "quick-prepare": "Verified the SSH host key",
            "quick-prep-mismatch": "Check Remote Login",
            "quick-prep-no-key": "Waiting for the guest SSH key",
            "quick-prep-invalid-key": "Invalid Ed25519 host key",
            "quick-prep-no-address": "Fusion has not reported a guest IPv4 address",
            "quick-prep-console": "Sign in to the guest desktop",
            "quick-prep-clt": "Finish the Command Line Tools installation",
        }
        for scenario, message in cases.items():
            with self.subTest(scenario=scenario):
                result, commands, files = self.run_case(
                    scenario, ("--prepare",), arch="x86_64", quick=True)
                self.assertEqual(result.returncode == 0, scenario == "quick-prepare", result.stderr)
                self.assertIn(message, result.stdout + result.stderr)
                self.assertFalse(any(cmd[0] == "clone" for cmd in commands))
                self.assertTrue(any(cmd[0] == "readVariable" for cmd in commands))
                if scenario == "quick-prepare":
                    self.assertIn("scripts/prepare-fusion-base.sh", files)
                    self.assertTrue({
                        "scripts/install-orbstack.sh", "scripts/install-gureum.sh",
                        "scripts/install-iterm2.sh", "scripts/vm-progress.sh",
                    }.issubset(files))
                else:
                    self.assertEqual(files, [])
                if scenario in ("quick-prep-no-key", "quick-prep-invalid-key"):
                    self.assertFalse(any(cmd[0] == "ssh" for cmd in commands))

    def test_intel_clones_transfers_verifies_and_cleans_up_through_fusion(self):
        result, commands, names = self.run_case(arch="x86_64", extra=("--delete-on-success",))
        self.assertEqual(result.returncode, 0, result.stderr)
        lifecycle = [cmd[0] for cmd in commands if cmd[0] != "list"]
        self.assertEqual(lifecycle, ["clone", "configure", "configure", "start", "getGuestIPAddress", "ssh", "ssh",
                                     "ssh", "ssh", "ssh", "ssh", "stop", "deleteVM"])
        destination = next(cmd[2] for cmd in commands if cmd[0] == "clone")
        self.assertEqual([cmd[1:] for cmd in commands if cmd[0] == "configure"],
                         [[destination, "isolation.tools.hgfs.disable", "TRUE"],
                          [destination, "sharedFolder.maxNum", "0"]])
        self.assertIn("scripts/vm-guest-path.sh", names)
        self.assertIn("scripts/vm-aqua-exec.py", names)
        verify = next(cmd for cmd in commands if "DOCKER_CONTEXT=colima-codyssey-verify" in cmd)
        self.assertTrue(verify[2].endswith("/vm-aqua-exec.py"))
        self.assertNotIn(".env", names)
        self.assertNotIn("gost/gost.yaml", names)
        self.assertIn("PASS:", result.stdout)

    def test_fusion_lost_preparation_reply_still_checks_guest_ownership(self):
        result, commands, _ = self.run_case("lost-prepare-reply", arch="x86_64")
        self.assertEqual(result.returncode, 255, result.stderr)
        self.assertTrue(any("--stop" in cmd for cmd in commands))
        self.assertFalse(any("DOCKER_CONTEXT=colima-codyssey-verify" in cmd for cmd in commands))

    def test_fusion_leaves_vm_running_when_guest_shutdown_is_unresolved(self):
        result, commands, _ = self.run_case("unresolved-guest-stop", ("--delete-on-success",), arch="x86_64")
        self.assertEqual(result.returncode, 255, result.stderr)
        self.assertTrue(any("--stop" in cmd for cmd in commands))
        self.assertFalse(any(cmd[0] in ("stop", "deleteVM") for cmd in commands))
        self.assertIn("retained without requesting shutdown", result.stderr)

    def test_fusion_offline_configuration_failure_keeps_the_clone_powered_off(self):
        result, commands, _ = self.run_case("offline-configuration-failure", arch="x86_64")
        self.assertEqual(result.returncode, 38, result.stderr)
        self.assertFalse(any(cmd[0] in ("start", "ssh", "deleteVM") for cmd in commands))
        self.assertIn("Offline clone retained for inspection", result.stdout)
        self.assertNotIn("Open:", result.stdout)
        self.assertNotIn("PASS:", result.stdout)

    def test_fusion_waits_for_shutdown_before_deleting(self):
        result, commands, _ = self.run_case("delayed-shutdown", ("--delete-on-success",), arch="x86_64")
        self.assertEqual(result.returncode, 0, result.stderr)
        verbs = [cmd[0] for cmd in commands]
        self.assertEqual(verbs[verbs.index("stop"):], ["stop", "list", "list", "deleteVM"])

    def test_fusion_collision_does_not_modify_existing_bundle(self):
        result, commands, _ = self.run_case("collision", ("--delete-on-success",), arch="x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [["list"]])

    def test_fusion_verification_or_stop_failure_retains_owned_vm(self):
        for scenario, code in (("verify-failure", 19), ("stop-failure", 1), ("shutdown-inventory-failure", 1)):
            with self.subTest(scenario=scenario):
                result, commands, _ = self.run_case(scenario, ("--delete-on-success",), arch="x86_64")
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertTrue(any(cmd[0] == "stop" for cmd in commands))
                self.assertFalse(any(cmd[0] == "deleteVM" for cmd in commands))
                self.assertNotIn("PASS:", result.stdout)
                if scenario == "stop-failure":
                    self.assertIn("stop was not confirmed", result.stdout)

    def test_linux_does_not_install_or_execute_tart(self):
        result, commands, _ = self.run_case("linux")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [])

    def test_install_failure_stops_before_vm_creation(self):
        result, commands, _ = self.run_case("install-failure")
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertEqual(commands, [])
        self.assertNotIn("PASS:", result.stdout)

    def test_preinstalled_checks_apps_and_cold_start_before_test_docker(self):
        result, commands, names = self.run_case(extra=("--preinstalled",))
        self.assertEqual(result.returncode, 0, result.stderr)
        def position(suffix):
            return next(i for i, cmd in enumerate(commands) if any(arg.endswith(suffix) for arg in cmd))
        self.assertLess(position("check-preinstalled-apps.py"), position("preinstalled-tools-test.py"))
        self.assertLess(position("preinstalled-tools-test.py"), position("prepare-macos-vm.sh"))
        self.assertLess(position("prepare-macos-vm.sh"), position("verify-macos-vm.sh"))
        self.assertIn("scripts/check-preinstalled-apps.py", names)
        self.assertTrue(any("DOCKER_CONTEXT=colima-codyssey-verify" in cmd for cmd in commands))

    def test_bad_preinstalled_image_fails_before_provisioning(self):
        result, commands, _ = self.run_case('preflight-failure', ('--preinstalled',))
        self.assertEqual(result.returncode, 21, result.stderr)
        self.assertFalse(any(any('prepare-macos-vm.sh' in arg for arg in cmd) for cmd in commands))
        self.assertIn(['stop', 'synthetic-test'], commands)
        self.assertNotIn('PASS:', result.stdout)

    def test_build_preinstalled_stops_and_retains_new_base_without_verification(self):
        result, commands, names = self.run_case(extra=("--build-preinstalled",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("READY: stopped preinstalled base", result.stdout)
        self.assertNotIn("PASS:", result.stdout)
        self.assertTrue(any(any("install-preinstalled-apps.sh" in arg for arg in cmd) for cmd in commands))
        self.assertFalse(any(any("verify-macos-vm.sh" in arg or "prepare-macos-vm.sh" in arg or "colima" in arg for arg in cmd) for cmd in commands))
        self.assertFalse(any(cmd[0] == "delete" for cmd in commands))
        self.assertIn("scripts/install-preinstalled-apps.sh", names)

    def test_build_base_refuses_delete_on_success_before_clone(self):
        result, commands, _ = self.run_case(extra=("--build-preinstalled", "--delete-on-success"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [])

    def test_success_can_delete_owned_vm(self):
        result, commands, _ = self.run_case(extra=("--delete-on-success",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["delete", "synthetic-test"], commands)

    def test_missing_check_input_stops_before_docker_build(self):
        with tempfile.TemporaryDirectory(prefix="vm-check-context-") as directory:
            work = Path(directory)
            source = work / "source"
            shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns(".git", "artifacts", ".env", "gost"))
            (source / "tests/managed-j-runtime.sh").unlink()
            fakebin = work / "bin"
            fakebin.mkdir()
            log = work / "docker.log"
            docker = fakebin / "docker"
            docker.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CHECK_DOCKER_LOG"\n')
            docker.chmod(0o755)
            result = subprocess.run(
                ["sh", str(source / "scripts/check.sh")],
                env=dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"],
                         CHECK_DOCKER_LOG=str(log)), text=True, capture_output=True, timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("managed-j-runtime.sh", result.stderr)
            self.assertEqual(log.read_text().splitlines(), ["version"])

    def test_collision_never_stops_or_deletes_existing_vm(self):
        result, commands, _ = self.run_case("collision", ("--delete-on-success",))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [["clone", "reviewed-base", "synthetic-test"]])

    def test_failures_are_propagated_and_retained(self):
        for scenario, code in (("set-failure", 1), ("boot-failure", 1), ("prepare-failure", 17), ("prepare-interrupt", 130), ("prepare-terminate", 143), ("verify-failure", 19), ("shutdown-failure", 1)):
            with self.subTest(scenario=scenario):
                result, commands, _ = self.run_case(scenario, ("--delete-on-success",))
                self.assertEqual(result.returncode, code, result.stderr)
                if scenario == "shutdown-failure":
                    self.assertNotIn(["stop", "synthetic-test"], commands)
                    self.assertIn("retained without requesting shutdown", result.stderr)
                else:
                    self.assertIn(["stop", "synthetic-test"], commands)
                self.assertFalse(any(cmd[0] == "delete" for cmd in commands))
                if scenario == "prepare-failure":
                    self.assertFalse(any(any("verify-macos-vm.sh" in arg for arg in cmd) for cmd in commands))

    def test_cleanup_failure_preserves_original_status_and_suppresses_pass(self) -> None:
        for scenario in ("verify-shutdown-failure", "verify-stop-failure"):
            with self.subTest(scenario=scenario):
                result, commands, _ = self.run_case(scenario, ("--delete-on-success",))
                self.assertEqual(result.returncode, 19, result.stderr)
                self.assertNotIn("PASS:", result.stdout)
                self.assertFalse(any(cmd[0] == "delete" for cmd in commands))

    def test_tart_stop_failure_never_claims_stopped_or_deletes(self) -> None:
        result, commands, _ = self.run_case("stop-failure", ("--delete-on-success",))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("retained (stopped)", result.stdout.lower())
        self.assertNotIn("PASS:", result.stdout)
        self.assertFalse(any(cmd[0] == "delete" for cmd in commands))

    def test_guest_agent_may_become_ready_after_initial_failures(self) -> None:
        result, _, _ = self.run_case("delayed-readiness")
        self.assertEqual(result.returncode, 0, result.stderr)

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
        for script in ("create-macos-vm.sh", "create-preinstalled-macos-image.sh", "prepare-macos-vm.sh", "verify-macos-vm.sh"):
            result = subprocess.run(["bash", str(ROOT / "scripts" / script), "--help"],
                                    text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            self.assertIn("Usage:", result.stdout)


class DesktopTransportTests(unittest.TestCase):
    def test_aqua_job_preserves_arguments_result_and_cleanup(self):
        run_in_aqua = runpy.run_path(str(ROOT / "scripts/vm-aqua-exec.py"))["run_in_aqua"]
        real_run = subprocess.run
        domains = []
        work = None

        def launchctl(argv, **kwargs):
            nonlocal work
            domains.append(argv[:3])
            if argv[1] == "bootstrap":
                file = Path(argv[3])
                work = file.parent
                job = plistlib.loads(file.read_bytes())
                self.assertEqual(job["LimitLoadToSessionType"], "Aqua")
                with Path(job["StandardOutPath"]).open("ab") as output:
                    real_run(job["ProgramArguments"], stdout=output, stderr=output, check=True)
            return subprocess.CompletedProcess(argv, 0)

        output = io.TextIOWrapper(io.BytesIO())
        with mock.patch.object(subprocess, "run", side_effect=launchctl), mock.patch.object(sys, "stdout", output):
            status = run_in_aqua(
                ["/bin/sh", "-c", 'printf "%s" "$1"; exit 17', "test", "guest's work"], 2
            )
        self.assertEqual(status, 17)
        self.assertEqual(output.buffer.getvalue(), b"guest's work")
        self.assertEqual([call[1] for call in domains], ["bootstrap", "bootout"])
        self.assertFalse(work.exists())

    def test_aqua_bootstrap_interruption_still_unregisters_the_job(self):
        run_in_aqua = runpy.run_path(str(ROOT / "scripts/vm-aqua-exec.py"))["run_in_aqua"]
        work = None
        target = None
        calls = []

        def launchctl(argv, **kwargs):
            nonlocal work, target
            calls.append(argv[1])
            if argv[1] == "bootstrap":
                file = Path(argv[3])
                work = file.parent
                target = f'{argv[2]}/{plistlib.loads(file.read_bytes())["Label"]}'
                raise SystemExit(143)
            self.assertEqual(argv[2], target)
            self.assertTrue(work.is_dir())
            return subprocess.CompletedProcess(argv, 0)

        with mock.patch.object(subprocess, "run", side_effect=launchctl):
            with self.assertRaises(SystemExit) as interrupted:
                run_in_aqua(["/usr/bin/true"], 2)
        self.assertEqual(interrupted.exception.code, 143)
        self.assertEqual(calls, ["bootstrap", "bootout"])
        self.assertFalse(work.exists())

    def test_tart_input_driver_transfers_the_verifier_path_helper(self):
        vnc = ModuleType("vncdotool")
        vnc.api = mock.Mock()
        with mock.patch.dict(sys.modules, {"vncdotool": vnc}):
            driver = runpy.run_path(str(ROOT / "scripts/verify-tart-input.py"))
        payload = None

        def guest(argv, **kwargs):
            nonlocal payload
            if "/usr/bin/mktemp" in argv:
                return subprocess.CompletedProcess(argv, 0, b"/tmp/codyssey-input.synthetic\n")
            if "/usr/bin/tar" in argv:
                payload = kwargs["input"]
            return subprocess.CompletedProcess(argv, 0, b"")

        with mock.patch.object(subprocess, "check_output", return_value="/fake/tart"), \
             mock.patch.object(subprocess, "run", side_effect=guest):
            with self.assertRaisesRegex(RuntimeError, "Expected one VNC endpoint"):
                with tempfile.TemporaryDirectory() as directory:
                    log = Path(directory) / "tart.log"
                    log.touch()
                    driver["run_check"]("synthetic", log)
        with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
            self.assertIn("scripts/verify-macos-vm.sh", archive.getnames())
            self.assertIn("scripts/vm-guest-path.sh", archive.getnames())


class UnattendedCacheTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.storage = self.work / "VM storage"
        self.bin = self.work / "bin"
        self.bin.mkdir()
        scripts = self.work / "scripts"
        numbered = scripts / "intel-macos-vm"
        numbered.mkdir(parents=True)
        shutil.copy(ROOT / "scripts/vm-fusion.sh", scripts)
        shutil.copy(ROOT / "scripts/vm-progress.sh", scripts)
        self.launcher = numbered / "run-unattended.sh"
        shutil.copy(ROOT / "scripts/intel-macos-vm" / self.launcher.name, self.launcher)
        for name, body in {
            "git": 'test "$3 $4 $5" = "rev-parse --verify HEAD" && printf "%s\\n" "$TEST_COMMIT"',
            "uname": 'case $1 in -s) echo Darwin;; -m) echo x86_64;; esac',
            "xcrun": "exit 0",
            "pgrep": "exit 1",
            "vmcli": "exit 0",
            "python3": '''case ${2:-} in
    'import socket;'*) echo 49152; exit 0;;
esac
exec "$TEST_PYTHON" "$@"''',
            "vmrun": '''case $3 in
    list) echo "Total running VMs: 0";;
    listSnapshots)
      test -f "${4%.vmx}.snapshot" || exit 3
      echo "macOS - initial setup complete";;
    *) exit 2;;
esac''',
        }.items():
            executable = self.bin / name
            executable.write_text(f"#!/bin/sh\n{body}\n")
            executable.chmod(0o755)
        for name, body in {
            "01-create-install-media.sh": '''mkdir -p "$CODYSSEY_FUSION_STORAGE/installers"
iso="$CODYSSEY_FUSION_STORAGE/installers/test.iso"
if [ ! -e "$iso" ]; then printf '%s\\n' "$TEST_COMMIT" > "$iso"; fi
printf '%s\\n' installers/test.iso > "$CODYSSEY_FUSION_STORAGE/current-installer"''',
            "02-create-base-vm.sh": '''directory="$CODYSSEY_FUSION_STORAGE/bases/Sequoia.vmwarevm"
mkdir -p "$directory"
touch "$directory/Sequoia.vmx"''',
            "04-checkpoint-and-mount-tools.sh": '''test -z "$TEST_FAIL_PREPARE" || exit 14
mkdir -p "$CODYSSEY_FUSION_CREDENTIALS"
printf "key\\n" > "$CODYSSEY_FUSION_IDENTITY"
printf "pin\\n" > "$CODYSSEY_FUSION_KNOWN_HOSTS"
touch "${1%.vmx}.snapshot"''',
            "06-verify-workstation.sh": '''test -f "$1"
test -s "$CODYSSEY_FUSION_IDENTITY"
test -s "$CODYSSEY_FUSION_KNOWN_HOSTS"
printf '%s\\n' "$1" > "$CODYSSEY_FUSION_STORAGE/verified-base"
test -z "$TEST_FAIL_VERIFY" || exit 16''',
            "07-close-fusion.sh": "",
        }.items():
            script = numbered / name
            script.write_text(f"set -eu\n{body}\n")
        (numbered / "install-guest.py").touch()
        self.commit = "1" * 40

    def run_launcher(self, *arguments, fail_prepare="", fail_verify=""):
        environment = dict(
            os.environ,
            PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
            CODYSSEY_FUSION_VMRUN=str(self.bin / "vmrun"),
            CODYSSEY_FUSION_STORAGE=str(self.storage),
            TEST_COMMIT=self.commit,
            TEST_PYTHON=sys.executable,
            TEST_FAIL_PREPARE=fail_prepare,
            TEST_FAIL_VERIFY=fail_verify,
        )
        result = subprocess.run(
            ["/bin/bash", str(self.launcher), "--accept-license", *arguments],
            env=environment, capture_output=True, text=True, timeout=15,
        )
        directory = next((Path(line[5:]) for line in result.stdout.splitlines()
                          if line.startswith("Run: ")), None)
        return result, directory

    def verified_base(self, *arguments):
        result, run = self.run_launcher(*arguments)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)
        return run, Path((run / "verified-base").read_text().strip())

    def test_cache_key_uses_commit_and_invalidation_is_explicit(self):
        first, base = self.verified_base()
        self.assertTrue((first / "04-prepare.log").is_file())
        (self.work / "scripts" / "dirty").write_text("uncommitted edit")
        repeat, reused = self.verified_base()
        self.assertEqual(reused, base)
        self.assertTrue((repeat / "base-reuse.log").is_file())
        self.assertFalse((repeat / "02-create.log").exists())
        self.commit = "2" * 40
        forced_reuse, reused = self.verified_base("--no-invalidate")
        self.assertEqual(reused, base)
        self.assertEqual((forced_reuse / "git-commit").read_text().strip(), self.commit)
        rebuilt = self.verified_base()[1]
        self.assertNotEqual(rebuilt, base)
        installer = self.storage / "installer-cache/installers/test.iso"
        self.assertEqual(installer.read_text().strip(), "1" * 40)
        self.assertNotEqual(self.verified_base("--invalidate")[1], rebuilt)
        self.assertTrue(base.is_file())

    def test_failure_invalidates_auto_reuse_but_leaves_the_prepared_base_available(self):
        result, failed = self.run_launcher(fail_verify="yes")
        self.assertEqual(result.returncode, 16, result.stderr)
        failed_base = Path((failed / "verified-base").read_text().strip())
        self.assertEqual(self.verified_base("--no-invalidate")[1], failed_base)
        result, _ = self.run_launcher(fail_verify="yes")
        self.assertEqual(result.returncode, 16, result.stderr)
        self.assertNotEqual(self.verified_base()[1], failed_base)

    def test_failed_preparation_and_missing_snapshot_cannot_be_reused(self):
        result, failed = self.run_launcher(fail_prepare="yes")
        self.assertEqual(result.returncode, 14, result.stderr)
        run, base = self.verified_base("--no-invalidate")
        self.assertNotEqual(run, failed)
        self.assertTrue((run / "04-prepare.log").is_file())
        base.with_suffix(".snapshot").unlink()
        self.assertNotEqual(self.verified_base("--no-invalidate")[1], base)

    def test_concurrent_invocation_does_not_change_the_cache(self):
        import fcntl

        self.verified_base()
        state = self.storage / "unattended-base"
        before = state.read_text()
        with (self.storage / ".unattended.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result, run = self.run_launcher("--invalidate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Another unattended Fusion run", result.stderr)
        self.assertIsNone(run)
        self.assertEqual(state.read_text(), before)


if __name__ == "__main__":
    unittest.main()
