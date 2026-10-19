#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
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
            "uname": '#!/bin/sh\n[ "${1:-}" = -m ] && echo arm64 || echo Darwin\n',
            "id": "#!/bin/sh\necho 501\n",
            "brew": "#!/bin/sh\nexit 0\n",
            "nc": "#!/bin/sh\nexit 1\n",
            "sleep": "#!/bin/sh\nexit 0\n",
            "zsh": "#!/bin/sh\nexit 0\n",
            "swift": "#!/bin/sh\nexit 0\n",
            "mise": '#!/bin/sh\necho "mise $*" >> "$VM_CALLS"\ncase "$*" in "install python@3.13.7") touch "$HOME/python-ready";; "where python@3.13.7") dirname "$0";; esac\n',

            "sh": "#!/bin/sh\nexit 0\n",
            "bash": '#!/bin/sh\nif [ "${1:-}" = init.sh ]; then grep -q "^# codyssey-init: mise$" "$HOME/.zshrc" 2>/dev/null || echo "# codyssey-init: mise" >> "$HOME/.zshrc"; fi\nexit 0\n',
            "python3": '#!/bin/sh\nif [ "$1" = -c ] && [ "${VM_GUEST_SCENARIO:-}" = preinstalled-old-python ] && [ ! -f "$HOME/python-ready" ]; then exit 1; fi\ncase "$*" in *verify-tailnet-runtime.py*) exit "${VM_LAB_STATUS:-0}";; *verify-macos-setup.py*) exit "${VM_LIVE_STATUS:-0}";; esac\ncat >/dev/null || true\nexit 0\n',
            "curl": '#!/bin/sh\ncase "$*" in *18081*) kind=ui; ready=${VM_UI_READY_AT:-1};; *) kind=api; ready=${VM_API_READY_AT:-1};; esac\ncount_file="$VM_CURL_COUNT-$kind"; count=0; [ ! -f "$count_file" ] || count=$(cat "$count_file"); count=$((count + 1)); echo "$count" > "$count_file"; [ "$count" -ge "$ready" ]\n',
            "colima": '#!/bin/sh\nprintf "%s\\n" "$*" >> "$VM_CALLS"\nif [ "$1" = stop ] && [ "${VM_GUEST_SCENARIO:-}" = docker-and-stop-failure ]; then exit 23; fi\nexit 0\n',
            "rm": '#!/bin/sh\nprintf "rm %s\\n" "$*" >> "$VM_CALLS"\nif [ "${VM_GUEST_SCENARIO:-}" = removal-failure ]; then case "${1:-}:${2:-}" in -rf:"$HOME"/codyssey-vm-test.*) exit 41;; esac; fi\nexec /bin/rm "$@"\n',
            "docker": "#!" + sys.executable + "\n" + r'''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["VM_CALLS"], "a") as stream:
    stream.write("docker " + " ".join(args) + "\n")
    if args and args[0] == "compose":
        stream.write("env " + json.dumps({key: os.environ.get(key) for key in ("DOCKER_CONTEXT", "DOCKER_HOST", "COMPOSE_FILE", "COMPOSE_ENV_FILES", "COMPOSE_PROJECT_NAME")}) + "\n")
scenario = os.environ.get("VM_GUEST_SCENARIO", "success")
if args == ["--context", "orbstack", "info"]:
    sys.exit(0 if scenario == "preinstalled-active" else 1)
if args == ["info"] and scenario.startswith("preinstalled"):
    marker = os.path.join(os.environ["HOME"], "orb-started")
    sys.exit(1 if scenario == "preinstalled-readiness-failure" or not os.path.exists(marker) else 0)
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
        # Repeated readiness probes must not launch an emulated Python runtime
        # sixty times. Keep info state in a shell wrapper; other Docker calls
        # still use the structured Python fixture below.
        backend = fakebin / "docker-backend"
        (fakebin / "docker").rename(backend)
        docker = fakebin / "docker"
        docker.write_text('#!/bin/sh\nif [ "$#" = 1 ] && [ "$1" = info ]; then\n  echo "docker info" >> "$VM_CALLS"\n  case "${VM_GUEST_SCENARIO:-}" in preinstalled*) [ "$VM_GUEST_SCENARIO" != preinstalled-readiness-failure ] && [ -f "$HOME/orb-started" ]; exit $?;; esac\n  exit 0\nfi\nexec "' + str(backend) + '" "$@"\n')
        docker.chmod(0o755)
        return fakebin

    def run_script(self, script: str, scenario: str = "success", extra: tuple[str, ...] = (), **overrides: str) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        with tempfile.TemporaryDirectory(prefix="vm-guest-") as directory:
            work = Path(directory)
            home = work / "home"
            (home / "Applications/Google Chrome.app").mkdir(parents=True)
            calls = work / "calls.log"
            env = dict(os.environ, HOME=str(home), VM_CALLS=str(calls),
                       VM_CURL_COUNT=str(work / "curl-count"), VM_GUEST_SCENARIO=scenario)
            env.pop("DOCKER_HOST", None)
            env.update(overrides)
            env["PATH"] = str(self.make_tools(work)) + os.pathsep + os.environ["PATH"]
            if scenario.startswith("preinstalled"):
                contents = home / "Applications/OrbStack.app/Contents/MacOS"
                (contents / "bin").mkdir(parents=True)
                (contents / "xbin").mkdir()
                orb = contents / "bin/orb"
                orb.write_text('#!/bin/sh\necho "orb $*" >> "$VM_CALLS"\nif [ "$1" = start ]; then touch "$HOME/orb-started"; fi\n')
                orb.chmod(0o700)
                (contents / "xbin/docker").symlink_to(work / "bin/docker")
                (home / "Library/Input Methods/Gureum.app").mkdir(parents=True)
                env.pop("DOCKER_CONTEXT", None)
            result = subprocess.run(["/bin/bash", str(ROOT / "scripts" / script), "--disposable", *extra],
                                    env=env, text=True, capture_output=True, timeout=25)
            return result, calls.read_text().splitlines() if calls.exists() else []

    def test_preinstalled_bootstraps_stopped_orbstack_and_stops_it_after_cleanup(self):
        result, calls = self.run_script("verify-macos-vm.sh", "preinstalled", extra=("--preinstalled",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.count("orb start"), 1)
        self.assertEqual(calls.count("orb stop"), 1)
        self.assertLess(calls.index("orb start"), next(i for i, call in enumerate(calls) if "compose" in call))
        self.assertLess(next(i for i, call in enumerate(calls) if "compose down" in call), calls.index("orb stop"))
        self.assertIn("PASS:", result.stdout)
        self.assertFalse(any("colima" in call for call in calls))

    def test_preinstalled_refuses_running_bundled_engine_without_stopping_it(self):
        result, calls = self.run_script("verify-macos-vm.sh", "preinstalled-active", extra=("--preinstalled",))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call.startswith("orb ") or "compose" in call for call in calls))

    def test_preinstalled_old_python_is_prepared_in_user_space(self):
        result, calls = self.run_script("verify-macos-vm.sh", "preinstalled-old-python", extra=("--preinstalled",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mise install python@3.13.7", calls)
        self.assertIn("mise where python@3.13.7", calls)
        self.assertEqual(calls.count("orb stop"), 1)

    def test_preinstalled_readiness_failure_stops_owned_engine_before_workloads(self):
        result, calls = self.run_script("verify-macos-vm.sh", "preinstalled-readiness-failure", extra=("--preinstalled",))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls.count("orb stop"), 1)
        self.assertFalse(any("compose" in call for call in calls))
        self.assertNotIn("PASS:", result.stdout)

    def test_preinstalled_refuses_target_override_before_engine_use(self):
        result, calls = self.run_script("verify-macos-vm.sh", extra=("--preinstalled",), DOCKER_HOST="tcp://remote:2376")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

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

    def test_verifier_refuses_preexisting_state_volume_without_cleanup(self) -> None:
        result, calls = self.run_script("verify-macos-vm.sh", "existing-volume")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("compose" in call for call in calls))
        self.assertFalse(any("volume rm" in call for call in calls))

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
        self.assertLess(result.stdout.index("COMPOSE_CLEANUP_COMPLETE"), result.stdout.index("PASS:"))

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

    def test_native_mode_schedules_only_original_python_suites(self) -> None:
        with tempfile.TemporaryDirectory(prefix="native-runner-") as directory:
            work = Path(directory)
            fakebin = work / "bin"
            fakebin.mkdir()
            calls = work / "calls.log"
            scripts = {
                "uname": "#!/bin/sh\necho Darwin\n",
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
            self.assertNotIn("tests/vm-guest-test.py", scheduled)


if __name__ == "__main__":
    unittest.main()
