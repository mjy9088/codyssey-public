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
    elif args[-1] == "--preflight" and scenario == "desktop-preflight-failure":
        sys.exit(21)
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
    assert args[2:] == ["full", "-cloneName=synthetic-test"]
    pathlib.Path(args[1]).touch()
elif command == "start":
    assert args[1:] == ["gui"]
    running.write_text(args[0])
elif command == "getGuestIPAddress":
    print("192.0.2.42")
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
if "--managed" in args and scenario in ("lost-prepare-reply", "unresolved-guest-stop"):
    sys.exit(255)
if "--stop" in args and scenario == "unresolved-guest-stop":
    print("Guest Colima preparation is still running.", file=sys.stderr)
    sys.exit(1)
if args[:2] == ["/bin/sh", "-c"]:
    if args[2].startswith("mktemp"):
        print("/Users/synthetic/guest's work")
elif args[0] == "/usr/bin/tar":
    assert args[1:] == ["-xf", "-", "-C", "/Users/synthetic/guest's work"]
    with tarfile.open(fileobj=sys.stdin.buffer, mode="r|*") as archive:
        names = [item.name for item in archive]
    with open(os.environ["VM_TEST_PAYLOAD"], "w") as stream:
        json.dump(names, stream)
elif len(args) > 1 and args[1].endswith("/vm-aqua-exec.py"):
    scenario = os.environ["VM_TEST_SCENARIO"]
    if args[-1] == "--preflight":
        if scenario == "desktop-preflight-failure":
            sys.exit(21)
    elif scenario == "verify-failure":
        sys.exit(19)
'''


class OrchestrationTests(unittest.TestCase):
    def run_case(self, scenario="success", extra=(), arch="arm64"):
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
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/create-macos-vm.sh"),
                 "--image", str(base) if arch == "x86_64" else "reviewed-base", "--name", "synthetic-test", *extra],
                cwd=work, env=env, text=True, capture_output=True, timeout=25,
            )
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

    def test_tart_checks_desktop_before_changing_guest_settings(self):
        for extra in ((), ("--workstation",)):
            with self.subTest(extra=extra):
                result, commands, _ = self.run_case(
                    "desktop-preflight-failure", (*extra, "--delete-on-success")
                )
                self.assertEqual(result.returncode, 21, result.stderr)
                self.assertTrue(any(cmd[-1] == "--preflight" for cmd in commands))
                self.assertIn("--request-access", result.stderr)
                self.assertFalse(any(
                    arg.endswith(("prepare-macos-vm.sh", "verify-macos-vm.sh"))
                    for cmd in commands for arg in cmd
                ))
                self.assertIn(["stop", "synthetic-test"], commands)
                self.assertFalse(any(cmd[0] == "delete" for cmd in commands))

    def test_intel_workstation_verifies_and_shuts_down_without_docker(self):
        result, commands, _ = self.run_case(arch="x86_64", extra=("--workstation",))
        self.assertEqual(result.returncode, 0, result.stderr)
        preflight = next(index for index, cmd in enumerate(commands) if cmd[-1] == "--preflight")
        verification = next(index for index, cmd in enumerate(commands) if cmd[-1] == "--workstation")
        shutdown = next(index for index, cmd in enumerate(commands) if cmd[0] == "stop")
        self.assertLess(preflight, verification)
        self.assertLess(verification, shutdown)
        self.assertFalse(any("prepare-macos-vm.sh" in arg or "DOCKER_CONTEXT" in arg
                             for cmd in commands for arg in cmd))

    def test_intel_clones_transfers_verifies_and_cleans_up_through_fusion(self):
        result, commands, names = self.run_case(arch="x86_64", extra=("--delete-on-success",))
        self.assertEqual(result.returncode, 0, result.stderr)
        lifecycle = [cmd[0] for cmd in commands if cmd[0] != "list"]
        self.assertEqual(lifecycle, ["clone", "configure", "configure", "start", "getGuestIPAddress", "ssh", "ssh",
                                     "ssh", "ssh", "ssh", "ssh", "ssh", "stop", "deleteVM"])
        destination = next(cmd[2] for cmd in commands if cmd[0] == "clone")
        self.assertEqual([cmd[1:] for cmd in commands if cmd[0] == "configure"],
                         [[destination, "isolation.tools.hgfs.disable", "TRUE"],
                          [destination, "sharedFolder.maxNum", "0"]])
        self.assertIn("scripts/vm-guest-path.sh", names)
        self.assertIn("scripts/vm-aqua-exec.py", names)
        preflight = next(cmd for cmd in commands if "--preflight" in cmd)
        verify = next(cmd for cmd in commands if "DOCKER_CONTEXT=colima-codyssey-verify" in cmd)
        self.assertTrue(preflight[2].endswith("/vm-aqua-exec.py"))
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

    def test_fusion_desktop_preflight_failure_prevents_provisioning(self):
        result, commands, _ = self.run_case("desktop-preflight-failure", arch="x86_64")
        self.assertEqual(result.returncode, 21, result.stderr)
        self.assertFalse(any("--managed" in cmd for cmd in commands))
        self.assertTrue(any(cmd[0] == "stop" for cmd in commands))

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


if __name__ == "__main__":
    unittest.main()
