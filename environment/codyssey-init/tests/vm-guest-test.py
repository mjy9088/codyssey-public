#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(sys.platform == "darwin", "guest fixtures run only in the Linux check container")
class GuestScriptTests(unittest.TestCase):
    def make_tools(self, work: Path) -> Path:
        fakebin = work / "bin"
        fakebin.mkdir()
        tools = {
            "uname": '#!/bin/sh\n[ "${1:-}" = -m ] && echo "${VM_TEST_GUEST_ARCH:-arm64}" || echo Darwin\n',
            "id": "#!/bin/sh\necho 501\n",
            "brew": "#!/bin/sh\nexit 0\n",
            "nc": "#!/bin/sh\nexit 1\n",
            "sleep": "#!/bin/sh\nexit 0\n",
            "zsh": "#!/bin/sh\nexit 0\n",
            "swift": "#!/bin/sh\nexit 0\n",

            "sh": "#!/bin/sh\nexit 0\n",
            "bash": '#!/bin/sh\nif [ "${1:-}" = init.sh ]; then grep -q "^# codyssey-init: mise$" "$HOME/.zshrc" 2>/dev/null || echo "# codyssey-init: mise" >> "$HOME/.zshrc"; fi\nexit 0\n',
            "python3": f'''#!/bin/sh
if [ "${{1:-}}" = -c ] && [ "$#" -ge 3 ]; then
    exec "{sys.executable}" "$@"
fi
case "$*" in
    *verify-tailnet-runtime.py*) exit "${{VM_LAB_STATUS:-0}}";;
    *verify-macos-setup.py*) exit "${{VM_LIVE_STATUS:-0}}";;
esac
cat >/dev/null || true
exit 0
''',
            "curl": '#!/bin/sh\ncase "$*" in *18081/health*) ready=${VM_UI_READY_AT:-1};; *) exit 7;; esac\ncount_file="$VM_CURL_COUNT"; count=0; [ ! -f "$count_file" ] || count=$(cat "$count_file"); count=$((count + 1)); echo "$count" > "$count_file"; [ "$count" -ge "$ready" ]\n',
            "colima": '''#!/bin/sh
printf '%s\\n' "$*" >> "$VM_CALLS"
case $1 in
    list)
        if [ "$VM_GUEST_SCENARIO" = inherited-running ]; then
            echo '{"name":"codyssey-verify","status":"Running","arch":"x86_64"}'
        fi
        ;;
    status)
        case ${VM_TEST_GUEST_ARCH:-arm64} in
            arm64) arch=x86_64 ;;
            x86_64) arch=aarch64 ;;
        esac
        driver=QEMU
        [ "$VM_GUEST_SCENARIO" != wrong-driver ] || driver=VZ
        printf '{"driver":"%s","arch":"%s","runtime":"docker"}\\n' "$driver" "$arch"
        ;;
    start)
        printf 'lima DHCP timeout %s\\n' "${LIMA_USERNET_RESOLVE_IP_ADDRESS_TIMEOUT:-unset}" >> "$VM_CALLS"
        ;;
    stop)
        if [ "$VM_GUEST_SCENARIO" = docker-and-stop-failure ]; then exit 23; fi
        ;;
esac
exit 0
''',
            "rm": '#!/bin/sh\nprintf "rm %s\\n" "$*" >> "$VM_CALLS"\nif [ "${VM_GUEST_SCENARIO:-}" = removal-failure ]; then case "${1:-}:${2:-}" in -rf:"$HOME"/codyssey-vm-test.*) exit 41;; esac; fi\nexec /bin/rm "$@"\n',
            "docker": "#!" + sys.executable + "\n" + r'''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["VM_CALLS"], "a") as stream:
    stream.write("docker " + " ".join(args) + "\n")
    if args and args[0] == "compose":
        stream.write("env " + json.dumps({key: os.environ.get(key) for key in ("DOCKER_CONTEXT", "DOCKER_HOST", "COMPOSE_FILE", "COMPOSE_ENV_FILES", "COMPOSE_PROJECT_NAME")}) + "\n")
scenario = os.environ.get("VM_GUEST_SCENARIO", "success")
if args[:2] == ["context", "show"]:
    print(os.environ.get("DOCKER_CONTEXT", "local-test")); sys.exit(0)
if args[:2] == ["context", "inspect"]:
    print(os.environ.get("VM_DOCKER_ENDPOINT", "unix:///tmp/docker.sock")); sys.exit(0)
if args[:2] == ["volume", "inspect"]:
    sys.exit(0 if scenario == "existing-volume" else 1)
if args[:2] == ["container", "inspect"]:
    sys.exit(1)
if args[:2] == ["compose", "exec"]:
    print('{"BackendState":"NeedsLogin"}'); sys.exit(0)
if args[:2] == ["compose", "version"] and scenario == "compose-version-failure":
    sys.exit(37)
if args[:2] == ["compose", "down"] and scenario == "compose-cleanup-failure":
    sys.exit(31)
if args[:2] == ["compose", "down"]:
    print("COMPOSE_CLEANUP_COMPLETE")
if args[:2] == ["--context", "colima-codyssey-verify"] and args[2:] == ["info"] and scenario in ("docker-readiness-failure", "docker-and-stop-failure"):
    sys.exit(17)
sys.exit(0)
''',
        }
        for name, script in tools.items():
            target = fakebin / name
            target.write_text(script)
            target.chmod(0o755)
        return fakebin

    def run_script(self, script: str, scenario: str = "success", managed: bool = False, cancel_before_start: bool = False, **overrides: str) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        with tempfile.TemporaryDirectory(prefix="vm-guest-") as directory:
            work = Path(directory)
            home = work / "home"
            (home / "Applications/Google Chrome.app").mkdir(parents=True)
            calls = work / "calls.log"
            env = dict(os.environ, HOME=str(home), VM_CALLS=str(calls),
                       VM_CURL_COUNT=str(work / "curl-count"), VM_GUEST_SCENARIO=scenario)
            env.pop("DOCKER_HOST", None)
            env.pop("LIMA_USERNET_RESOLVE_IP_ADDRESS_TIMEOUT", None)
            env.update(overrides)
            tools = self.make_tools(work)
            if scenario == "intel-macports":
                for name in ("port", "limactl", "qemu-system-aarch64", "node"):
                    shutil.copy(tools / "sh", tools / name)
                (tools / "brew").write_text("#!/bin/sh\nexit 51\n")
            env["PATH"] = str(tools) + os.pathsep + os.environ["PATH"]
            # QEMU TCG measured over 25 seconds for full verifier fixtures; keep
            # every assertion while allowing bounded emulated process startup.
            source = ROOT
            if managed or cancel_before_start:
                source = work / "guest transfer"
                (source / "scripts").mkdir(parents=True)
                (source / "lib").mkdir()
                for path in (f"scripts/{script}", "scripts/vm-guest-path.sh", "lib/preparation.sh"):
                    shutil.copy(ROOT / path, source / path)
            command = ["/bin/bash", str(source / "scripts" / script), "--disposable"]
            options = dict(env=env, text=True, capture_output=True, timeout=120)
            if cancel_before_start:
                cancelled = subprocess.run([*command, "--stop"], **options)
                self.assertEqual(cancelled.returncode, 0, cancelled.stderr)
                result = subprocess.run([*command, "--managed"], **options)
            elif managed:
                prepared = subprocess.run([*command, "--managed"], **options)
                self.assertEqual(prepared.returncode, 0, prepared.stderr)
                # Stop from a new invocation with no parent or preparation status in memory.
                self.assertTrue((home / ".codyssey-verify-colima/owner").is_file())
                result = subprocess.run([*command, "--stop"], **options)
                self.assertFalse((home / ".codyssey-verify-colima").exists())
                repeated = subprocess.run([*command, "--stop"], **options)
                self.assertEqual(repeated.returncode, 0, repeated.stderr)
            else:
                result = subprocess.run(command, **options)
            return result, calls.read_text().splitlines() if calls.exists() else []

    def test_preparer_uses_foreign_architecture_on_each_mac(self) -> None:
        for guest, linux in (("arm64", "x86_64"), ("x86_64", "aarch64")):
            with self.subTest(guest=guest):
                result, calls = self.run_script("prepare-macos-vm.sh", VM_TEST_GUEST_ARCH=guest)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(any(call.startswith(
                    f"start --profile codyssey-verify --vm-type qemu --arch {linux} "
                ) for call in calls))
                self.assertIn("lima DHCP timeout 10", calls)

    def test_preparer_honors_explicit_lima_dhcp_timeout(self) -> None:
        result, calls = self.run_script(
            "prepare-macos-vm.sh", LIMA_USERNET_RESOLVE_IP_ADDRESS_TIMEOUT="15"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lima DHCP timeout 15", calls)

    def test_preparer_publishes_managed_ownership_for_a_later_stop(self) -> None:
        result, calls = self.run_script("prepare-macos-vm.sh", managed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.count("stop --profile codyssey-verify"), 1)

    def test_intel_preparer_uses_macports_tools_without_running_homebrew(self) -> None:
        result, calls = self.run_script(
            "prepare-macos-vm.sh", scenario="intel-macports", VM_TEST_GUEST_ARCH="x86_64"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("docker compose version", calls)
        self.assertIn("docker buildx version", calls)
        self.assertTrue(any("--vm-type qemu --arch aarch64" in call for call in calls))

    def test_preparer_cannot_start_after_host_cancels_before_ownership(self) -> None:
        result, calls = self.run_script("prepare-macos-vm.sh", cancel_before_start=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("preparation was cancelled", result.stderr)
        self.assertFalse(any(call.startswith(("start ", "stop ")) for call in calls))

    def test_preparer_rejects_inherited_running_profile_without_stopping_it(self) -> None:
        result, calls = self.run_script("prepare-macos-vm.sh", "inherited-running")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be stopped", result.stderr)
        self.assertFalse(any(call.startswith(("start ", "stop ")) for call in calls))

    def test_preparer_rejects_unexpected_running_driver_and_stops_owned_profile(self) -> None:
        result, calls = self.run_script("prepare-macos-vm.sh", "wrong-driver")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must use QEMU", result.stderr)
        self.assertIn("stop --profile codyssey-verify", calls)

    def test_prepare_stops_owned_colima_after_readiness_failure(self) -> None:
        result, calls = self.run_script("prepare-macos-vm.sh", "docker-readiness-failure")
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertIn("stop --profile codyssey-verify", calls)

    def test_prepare_preserves_readiness_status_when_colima_stop_also_fails(self) -> None:
        result, calls = self.run_script("prepare-macos-vm.sh", "docker-and-stop-failure")
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertIn("stop --profile codyssey-verify", calls)

    def test_verifier_rejects_remote_context_before_compose_or_volume_cleanup(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", VM_DOCKER_ENDPOINT="tcp://remote:2376")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("compose" in call or "volume" in call for call in calls))

    def test_verifier_rejects_docker_host_before_docker_use(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", DOCKER_HOST="unix:///tmp/override.sock")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_verifier_never_uses_legacy_state_volume(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", "existing-volume")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call.startswith("docker volume ") for call in calls))
        self.assertIn("docker compose down --volumes", calls)

    def test_verifier_cleans_work_after_compose_version_failure_without_down(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", "compose-version-failure")
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertNotIn("PASS:", result.stdout)
        self.assertFalse(any("compose down" in call for call in calls))
        self.assertEqual(sum(call.startswith("rm -rf ") and "codyssey-vm-test." in call for call in calls), 1)

    def test_verifier_delays_pass_until_cleanup_and_ui_readiness(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", VM_UI_READY_AT="4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS:", result.stdout)
        self.assertEqual(sum("compose down --volumes" in call for call in calls), 1)
        self.assertNotIn("COMPOSE_CLEANUP_COMPLETE", result.stdout)

    def test_verifier_local_lab_failure_prevents_success_and_cleans(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", VM_LAB_STATUS="27")
        self.assertEqual(result.returncode, 27, result.stderr)
        self.assertNotIn("PASS:", result.stdout)
        self.assertEqual(sum("compose down --volumes" in call for call in calls), 1)

    def test_verifier_freezes_context_and_clears_compose_overrides(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", DOCKER_CONTEXT="local-test",
                                        COMPOSE_FILE="/tmp/hostile.yml", COMPOSE_ENV_FILES="/tmp/hostile.env")
        self.assertEqual(result.returncode, 0, result.stderr)
        environments = [json.loads(call.removeprefix("env ")) for call in calls if call.startswith("env ")]
        self.assertTrue(environments)
        self.assertTrue(all(item["DOCKER_CONTEXT"] == "local-test" for item in environments))
        self.assertTrue(all(item["DOCKER_HOST"] is None for item in environments))
        self.assertTrue(all(item["COMPOSE_FILE"] is None and item["COMPOSE_ENV_FILES"] is None for item in environments))
        projects = [item["COMPOSE_PROJECT_NAME"] for item in environments if item["COMPOSE_PROJECT_NAME"] is not None]
        self.assertTrue(projects)
        self.assertTrue(all(item.startswith("codyssey-vm-verify-") for item in projects))

    def test_verifier_cleanup_failure_suppresses_pass_and_preserves_error(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", "compose-cleanup-failure", VM_LIVE_STATUS="19")
        self.assertEqual(result.returncode, 19, result.stderr)
        self.assertNotIn("PASS:", result.stdout)
        self.assertEqual(sum("compose down --volumes" in call for call in calls), 1)

    def test_verifier_cleanup_failure_after_success_returns_nonzero(self) -> None:
        result, _ = self.run_script("verify-macos-vm.sh", "compose-cleanup-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PASS:", result.stdout)

    def test_verifier_work_removal_failure_is_reported_and_preserves_status(self) -> None:
        for live_status, expected in (("0", 1), ("19", 19)):
            with self.subTest(live_status=live_status):
                result, calls = self.run_script("verify-macos-vm.sh", "removal-failure", VM_LIVE_STATUS=live_status)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertNotIn("PASS:", result.stdout)
                self.assertIn("private working directory retained at", result.stderr)
                self.assertEqual(sum(call.startswith("rm -rf ") for call in calls), 1)

    def test_native_python_linux_rejection_is_explanatory(self) -> None:
        result = subprocess.run(["sh", str(ROOT / "scripts/check.sh"), "--native-python"],
                                text=True, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("macOS", result.stderr)

    def test_native_mode_schedules_python_and_gureum_suites(self) -> None:
        with tempfile.TemporaryDirectory(prefix="native-runner-") as directory:
            work = Path(directory)
            fakebin = work / "bin"
            fakebin.mkdir()
            calls = work / "calls.log"
            scripts = {
                "uname": "#!/bin/sh\necho Darwin\n",
                "bash": '#!/bin/sh\nprintf "bash %s\\n" "$*" >> "$RUNNER_CALLS"\n',
                "python3": '#!/bin/sh\nprintf "python3 %s\\n" "$*" >> "$RUNNER_CALLS"\n',
                "docker": '#!/bin/sh\nprintf "docker %s\\n" "$*" >> "$RUNNER_CALLS"\n[ "${1:-}" != build ] || cat >/dev/null\n',
            }
            for name, script in scripts.items():
                target = fakebin / name
                target.write_text(script)
                target.chmod(0o755)
            env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"], RUNNER_CALLS=str(calls))
            result = subprocess.run(["sh", str(ROOT / "scripts/check.sh"), "--native-python"],
                                    env=env, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            scheduled = calls.read_text()
            self.assertIn("tests/macos-setup-test.py", scheduled)
            self.assertIn("tests/vm-orchestration-test.py", scheduled)
            self.assertIn("tests/gureum-activation-test.sh", scheduled)
            self.assertNotIn("tests/vm-guest-test.py", scheduled)


if __name__ == "__main__":
    unittest.main()
