#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import pty
import select
import shutil
import stat
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Final, TypeAlias

ROOT: Final = Path(__file__).resolve().parents[1]
TEXT_KEYS: Final = (
    "NSAutomaticCapitalizationEnabled",
    "NSAutomaticPeriodSubstitutionEnabled",
    "NSAutomaticSpellingCorrectionEnabled",
    "WebAutomaticSpellingCorrectionEnabled",
    "NSAutomaticInlinePredictionEnabled",
    "NSAutomaticTextCompletionEnabled",
    "NSAutomaticQuoteSubstitutionEnabled",
    "NSAutomaticDashSubstitutionEnabled",
    "NSAutomaticTextReplacementEnabled",
)
PlistValue: TypeAlias = str | bytes | int | float | bool | list["PlistValue"] | dict[str, "PlistValue"]


def state_path(state: Path, domain: str) -> Path:
    return state / f"{domain.encode().hex()}.plist"


def write_domain(state: Path, domain: str, value: dict[str, PlistValue]) -> None:
    with state_path(state, domain).open("wb") as stream:
        plistlib.dump(value, stream, sort_keys=True)


def read_domain(state: Path, domain: str) -> dict[str, PlistValue]:
    with state_path(state, domain).open("rb") as stream:
        value = plistlib.load(stream)
    assert isinstance(value, dict)
    return value


def baseline(state: Path) -> None:
    write_domain(state, "NSGlobalDomain", {key: True for key in TEXT_KEYS} | {"UnrelatedText": "keep"})
    write_domain(
        state,
        "com.apple.dock",
        {"persistent-apps": [{"old": "pin"}], "persistent-others": [{"old": "stack"}], "show-recents": True, "static-only": True},
    )
    write_domain(
        state,
        "com.apple.HIToolbox",
        {"AppleEnabledInputSources": [{"InputSourceKind": "Keyboard Layout", "KeyboardLayout Name": "ABC"}], "UnrelatedInput": 7},
    )
    write_domain(state, "com.apple.symbolichotkeys", {"AppleSymbolicHotKeys": {"99": {"enabled": True}}, "UnrelatedHotkey": "keep"})


def environment(root: Path) -> tuple[dict[str, str], Path]:
    state = root / "state"
    state.mkdir()
    fake_bin = root / "bin"
    fake_bin.mkdir()
    tool = fake_bin / "fake-tools.py"
    shutil.copyfile(ROOT / "tests" / "macos-fake-tools.py", tool)
    tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
    for name in ("defaults", "PlistBuddy", "plutil", "uname", "killall"):
        (fake_bin / name).symlink_to(tool)
    home = root / "home"
    (home / "Applications" / "Google Chrome.app").mkdir(parents=True)
    applications = root / "Applications"
    systems = root / "System" / "Applications"
    (systems / "Utilities" / "Terminal.app").mkdir(parents=True)
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "CODYSSEY_DOCK_SETUP": "1",
            "USER": "test-user",
            "FAKE_DEFAULTS_STATE": str(state),
            "UNAME_BIN": str(fake_bin / "uname"),
            "DEFAULTS_BIN": str(fake_bin / "defaults"),
            "PLISTBUDDY_BIN": str(fake_bin / "PlistBuddy"),
            "PLUTIL_BIN": str(fake_bin / "plutil"),
            "KILLALL_BIN": str(fake_bin / "killall"),
            "CODYSSEY_APPLICATIONS_DIR": str(applications),
            "CODYSSEY_SYSTEM_APPLICATIONS_DIR": str(systems),
        }
    )
    env.pop("CODYSSEY_INPUT_SWITCH", None)
    return env, state


def apply(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(("bash", str(ROOT / "macos-setup.sh")), env=env, text=True, capture_output=True, check=False)


def assert_success_contract(state: Path) -> None:
    text = read_domain(state, "NSGlobalDomain")
    assert all(text[key] is False for key in TEXT_KEYS)
    assert text["UnrelatedText"] == "keep"
    assert text["TISRomanSwitchState"] == 0
    dock = read_domain(state, "com.apple.dock")
    assert dock["show-recents"] is False and dock["static-only"] is False
    others = dock["persistent-others"]
    assert len(others) == 1
    assert others[0]["tile-data"]["file-data"]["_CFURLString"].endswith("/Codyssey%20j.command")
    apps = dock["persistent-apps"]
    assert isinstance(apps, list)
    urls: list[PlistValue] = []
    for entry in apps:
        assert isinstance(entry, dict)
        tile_data = entry["tile-data"]
        assert isinstance(tile_data, dict)
        file_data = tile_data["file-data"]
        assert isinstance(file_data, dict)
        urls.append(file_data["_CFURLString"])
    assert len(urls) == 2
    assert urls[0].startswith("file://") and urls[0].endswith("/System/Applications/Utilities/Terminal.app/")
    assert urls[1].startswith("file://") and urls[1].endswith("/home/Applications/Google%20Chrome.app/")
    sources = read_domain(state, "com.apple.HIToolbox")["AppleEnabledInputSources"]
    assert isinstance(sources, list) and isinstance(sources[0], dict)
    assert sources[0]["KeyboardLayout Name"] == "ABC"
    assert sources.count({"InputSourceKind": "Input Mode", "Bundle ID": "org.youknowone.inputmethod.Gureum", "Input Mode": "org.youknowone.inputmethod.Gureum.han2"}) == 1
    hotkeys = read_domain(state, "com.apple.symbolichotkeys")["AppleSymbolicHotKeys"]
    assert isinstance(hotkeys, dict) and hotkeys["99"] == {"enabled": True}
    assert hotkeys["60"] == {"enabled": True, "value": {"type": "standard", "parameters": [65535, 49, 262144]}}
    assert hotkeys["61"] == {"enabled": True, "value": {"type": "standard", "parameters": [65535, 49, 393216]}}


def test_success_and_repeat() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        first = apply(env)
        assert first.returncode == 0, first.stderr
        assert_success_contract(state)
        before = {path.name: path.read_bytes() for path in state.glob("*.plist")}
        second = apply(env)
        assert second.returncode == 0, second.stderr
        assert before == {path.name: path.read_bytes() for path in state.glob("*.plist")}
        backups = list((Path(env["HOME"]) / "Library/Application Support/codyssey-init/macos-backups").glob("*"))
        assert len(backups) == 2 and all(stat.S_IMODE(path.stat().st_mode) == 0o700 for path in backups)
        assert all(stat.S_IMODE(item.stat().st_mode) == 0o600 for path in backups for item in path.iterdir())
        calls = (state / "calls.log").read_text()
        assert "killall\t-u test-user Dock" in calls
        assert "activateSettings" not in calls
        assert ":'Bundle ID'" in calls and ":'Input Mode'" in calls


def test_missing_chrome_preserves_dock_and_adds_launcher() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = read_domain(state, "com.apple.dock")
        (Path(env["HOME"]) / "Applications" / "Google Chrome.app").rmdir()
        result = apply(env)
        assert result.returncode == 0
        dock = read_domain(state, "com.apple.dock")
        assert dock["persistent-apps"] == original["persistent-apps"]
        assert dock["show-recents"] == original["show-recents"]
        assert dock["persistent-others"][0] == original["persistent-others"][0]
        assert len(dock["persistent-others"]) == 2
        assert apply(env).returncode == 0
        assert read_domain(state, "com.apple.dock") == dock


def test_export_and_write_failures_are_isolated_and_rolled_back() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original_text = state_path(state, "NSGlobalDomain").read_bytes()
        original_input = state_path(state, "com.apple.HIToolbox").read_bytes()
        env["FAKE_WRITE"] = "NSGlobalDomain:NSAutomaticSpellingCorrectionEnabled"
        env["FAKE_EXPORT"] = "com.apple.HIToolbox"
        result = apply(env)
        assert result.returncode == 1
        assert "continuing remaining groups" in result.stderr
        remaining_text = read_domain(state, "NSGlobalDomain")
        assert remaining_text.pop("TISRomanSwitchState") == 0
        assert remaining_text == plistlib.loads(original_text)
        assert state_path(state, "com.apple.HIToolbox").read_bytes() == original_input
        assert read_domain(state, "com.apple.dock")["show-recents"] is False
        hotkeys = read_domain(state, "com.apple.symbolichotkeys")["AppleSymbolicHotKeys"]
        assert hotkeys["60"]["value"]["parameters"] == [65535, 49, 262144]


def test_absent_domain_is_created_only_after_confirmed_absent() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        state_path(state, "com.apple.symbolichotkeys").unlink()
        result = apply(env)
        assert result.returncode == 0
        hotkeys = read_domain(state, "com.apple.symbolichotkeys")["AppleSymbolicHotKeys"]
        assert isinstance(hotkeys, dict) and set(hotkeys) == {"60", "61", "64", "65"}
        backup_root = Path(env["HOME"]) / "Library/Application Support/codyssey-init/macos-backups"
        assert len(list(backup_root.glob("*/hotkeys.missing"))) == 1


def test_last_existing_domain_export_failure_is_not_absence() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = state_path(state, "com.apple.symbolichotkeys").read_bytes()
        env["FAKE_EXPORT"] = "com.apple.symbolichotkeys"
        result = apply(env)
        assert result.returncode == 1
        assert state_path(state, "com.apple.symbolichotkeys").read_bytes() == original
        backup_root = Path(env["HOME"]) / "Library/Application Support/codyssey-init/macos-backups"
        assert list(backup_root.glob("*/hotkeys.missing")) == []


def run_verifier(env: dict[str, str], *arguments: str) -> subprocess.CompletedProcess[str]:
    verifier_env = env | {"CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST": "1"}
    return subprocess.run(("python3", str(ROOT / "verify-macos-setup.py"), *arguments), env=verifier_env, text=True, capture_output=True, check=False)


def test_verifier_leaves_applied_state_on_success_and_restores_on_failure() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        success = run_verifier(env)
        assert success.returncode == 0, success.stderr
        assert_success_contract(state)

    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = {path.name: path.read_bytes() for path in state.glob("*.plist")}
        env["FAKE_WRITE"] = "NSGlobalDomain:NSAutomaticSpellingCorrectionEnabled"
        failure = run_verifier(env)
        assert failure.returncode != 0
        assert original == {path.name: path.read_bytes() for path in state.glob("*.plist")}


def test_verifier_retains_snapshot_when_restoration_fails() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = {path.name: path.read_bytes() for path in state.glob("*.plist")}
        env["FAKE_WRITE"] = "NSGlobalDomain:NSAutomaticSpellingCorrectionEnabled"
        env["FAKE_IMPORT_AT"] = "NSGlobalDomain:3"
        failure = run_verifier(env)
        assert failure.returncode != 0
        marker = "backup retained at "
        assert marker in failure.stderr
        retained_line = next(line for line in failure.stderr.splitlines() if line.startswith("restoration failed for "))
        retained = Path(retained_line.partition(marker)[2])
        assert retained.is_dir() and stat.S_IMODE(retained.stat().st_mode) == 0o700, failure.stderr
        current = {path.name: path.read_bytes() for path in state.glob("*.plist")}
        failed_name = state_path(state, "NSGlobalDomain").name
        assert all(current[name] == contents for name, contents in original.items() if name != failed_name)
        shutil.rmtree(retained)


def test_verifier_restores_after_keyboard_interrupt() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = {path.name: path.read_bytes() for path in state.glob("*.plist")}
        env["FAKE_INTERRUPT_AT"] = "com.apple.symbolichotkeys:1"
        interrupted = run_verifier(env)
        assert interrupted.returncode != 0
        assert "KeyboardInterrupt" in interrupted.stderr
        assert original == {path.name: path.read_bytes() for path in state.glob("*.plist")}


def test_launcher_executes_from_another_directory_and_preserves_arguments() -> None:
    with tempfile.TemporaryDirectory(prefix="launcher's ") as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        assert apply(env).returncode == 0
        launcher = Path(env["HOME"]) / "Library/Application Support/codyssey-init/Codyssey j.command"
        assert stat.S_IMODE(launcher.stat().st_mode) == 0o700
        fake = Path(env["HOME"]) / ".local/bin/just"
        fake.parent.mkdir(parents=True)
        fake.write_text('#!/bin/sh\nprintf "cwd=%s\\n" "$PWD"\nprintf "arg=%s\\n" "$@"\nexit 29\n')
        fake.chmod(0o700)
        zsh = shutil.which("zsh")
        assert zsh, "zsh is required to exercise the terminal launcher"
        result = subprocess.run([zsh, str(launcher), "two words", "*"], cwd="/", env=env, text=True, capture_output=True)
        assert result.returncode == 29, result.stderr
        assert result.stdout.splitlines() == [f"cwd={ROOT}", "arg=two words", "arg=*"]
        launcher.write_text("user owned\n")
        result = apply(env)
        assert result.returncode == 1
        assert launcher.read_text() == "user owned\n"


def test_desktop_verifier_preserves_keyboard_and_text() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = {domain: read_domain(state, domain) for domain in ("NSGlobalDomain", "com.apple.HIToolbox", "com.apple.symbolichotkeys")}
        just = Path(env["HOME"]) / ".local/bin/just"
        just.parent.mkdir(parents=True)
        just.write_text("#!/bin/sh\ntest \"$1\" = --list\n")
        just.chmod(0o700)
        env["CODYSSEY_DOCK_SETUP"] = "0"
        result = run_verifier(env, "--desktop-only")
        assert result.returncode == 0, result.stderr
        assert all(read_domain(state, domain) == value for domain, value in original.items())
        assert len(read_domain(state, "com.apple.dock")["persistent-others"]) == 1


def test_keep_dock_adds_launcher_once_and_rolls_back_failure() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        env["CODYSSEY_DOCK_SETUP"] = "0"
        original = read_domain(state, "com.apple.dock")
        assert apply(env).returncode == 0
        first = read_domain(state, "com.apple.dock")
        assert first["persistent-apps"] == original["persistent-apps"]
        assert first["show-recents"] == original["show-recents"]
        assert first["persistent-others"][0] == original["persistent-others"][0]
        assert len(first["persistent-others"]) == 2
        assert apply(env).returncode == 0
        assert read_domain(state, "com.apple.dock") == first
        write_domain(state, "com.apple.dock", original)
        env["FAKE_WRITE"] = "com.apple.dock:persistent-others"
        assert apply(env).returncode == 1
        assert read_domain(state, "com.apple.dock") == original


def test_interactive_dock_default_and_decline() -> None:
    for answer in (b"\n", b"n\n"):
        with tempfile.TemporaryDirectory() as temporary:
            env, state = environment(Path(temporary))
            baseline(state)
            original = read_domain(state, "com.apple.dock")
            env.pop("CODYSSEY_DOCK_SETUP", None)
            pid, terminal = pty.fork()
            if pid == 0:
                os.execvpe("bash", ["bash", str(ROOT / "macos-setup.sh")], env)
            output = b""
            answered = False
            status = None
            try:
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if select.select([terminal], [], [], 0.1)[0]:
                        try:
                            chunk = os.read(terminal, 65536)
                        except OSError:
                            chunk = b""
                            time.sleep(0.02)
                        output += chunk
                        if not answered and b"[Y/n] " in output:
                            os.write(terminal, answer)
                            answered = True
                    child, status = os.waitpid(pid, os.WNOHANG)
                    if child:
                        break
                    status = None
                if status is None:
                    child, status = os.waitpid(pid, os.WNOHANG)
                    if not child:
                        os.kill(pid, 9)
                        os.waitpid(pid, 0)
                        raise AssertionError("Dock prompt did not finish: " + output.decode(errors="replace"))
                assert answered and os.waitstatus_to_exitcode(status) == 0, output
            finally:
                os.close(terminal)
            dock = read_domain(state, "com.apple.dock")
            if answer == b"\n":
                assert_success_contract(state)
            else:
                assert dock["persistent-apps"] == original["persistent-apps"]
                assert dock["persistent-others"][0] == original["persistent-others"][0]
                assert len(dock["persistent-others"]) == 2


def main() -> None:
    test_interactive_dock_default_and_decline()
    test_keep_dock_adds_launcher_once_and_rolls_back_failure()
    test_desktop_verifier_preserves_keyboard_and_text()
    test_launcher_executes_from_another_directory_and_preserves_arguments()
    test_success_and_repeat()
    test_missing_chrome_preserves_dock_and_adds_launcher()
    test_export_and_write_failures_are_isolated_and_rolled_back()
    test_absent_domain_is_created_only_after_confirmed_absent()
    test_last_existing_domain_export_failure_is_not_absence()
    test_verifier_leaves_applied_state_on_success_and_restores_on_failure()
    test_verifier_retains_snapshot_when_restoration_fails()
    test_verifier_restores_after_keyboard_interrupt()
    print("macOS setup isolated tests: 12 passed")


if __name__ == "__main__":
    main()
