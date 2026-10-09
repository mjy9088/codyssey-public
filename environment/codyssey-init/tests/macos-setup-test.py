#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import shutil
import stat
import subprocess
import tempfile
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
    return env, state


def apply(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(("bash", str(ROOT / "macos-setup.sh")), env=env, text=True, capture_output=True, check=False)


def assert_success_contract(state: Path) -> None:
    text = read_domain(state, "NSGlobalDomain")
    assert all(text[key] is False for key in TEXT_KEYS)
    assert text["UnrelatedText"] == "keep"
    dock = read_domain(state, "com.apple.dock")
    assert dock["show-recents"] is False and dock["static-only"] is False
    assert dock["persistent-others"] == []
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
    assert sources.count({"InputSourceKind": "Input Mode", "Bundle ID": "com.apple.inputmethod.Korean", "Input Mode": "com.apple.inputmethod.Korean.2SetKorean"}) == 1
    hotkeys = read_domain(state, "com.apple.symbolichotkeys")["AppleSymbolicHotKeys"]
    assert isinstance(hotkeys, dict) and hotkeys["99"] == {"enabled": True}
    assert hotkeys["60"] == {"enabled": True, "value": {"type": "standard", "parameters": [32, 49, 262144]}}
    assert hotkeys["61"] == {"enabled": True, "value": {"type": "standard", "parameters": [32, 49, 786432]}}


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


def test_missing_chrome_preserves_entire_dock() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = state_path(state, "com.apple.dock").read_bytes()
        (Path(env["HOME"]) / "Applications" / "Google Chrome.app").rmdir()
        result = apply(env)
        assert result.returncode == 0
        assert state_path(state, "com.apple.dock").read_bytes() == original


def test_export_and_write_failures_are_isolated_and_rolled_back() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original_text = state_path(state, "NSGlobalDomain").read_bytes()
        original_input = state_path(state, "com.apple.HIToolbox").read_bytes()
        env["FAKE_WRITE"] = "NSGlobalDomain:NSAutomaticSpellingCorrectionEnabled"
        env["FAKE_EXPORT"] = "com.apple.HIToolbox"
        result = apply(env)
        assert result.returncode == 0
        assert state_path(state, "NSGlobalDomain").read_bytes() == original_text
        assert state_path(state, "com.apple.HIToolbox").read_bytes() == original_input
        assert read_domain(state, "com.apple.dock")["show-recents"] is False
        assert "AppleSymbolicHotKeys" in read_domain(state, "com.apple.symbolichotkeys")


def test_absent_domain_is_created_only_after_confirmed_absent() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        state_path(state, "com.apple.symbolichotkeys").unlink()
        result = apply(env)
        assert result.returncode == 0
        hotkeys = read_domain(state, "com.apple.symbolichotkeys")["AppleSymbolicHotKeys"]
        assert isinstance(hotkeys, dict) and set(hotkeys) == {"60", "61"}
        backup_root = Path(env["HOME"]) / "Library/Application Support/codyssey-init/macos-backups"
        assert len(list(backup_root.glob("*/hotkeys.missing"))) == 1


def test_last_existing_domain_export_failure_is_not_absence() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        env, state = environment(Path(temporary))
        baseline(state)
        original = state_path(state, "com.apple.symbolichotkeys").read_bytes()
        env["FAKE_EXPORT"] = "com.apple.symbolichotkeys"
        result = apply(env)
        assert result.returncode == 0
        assert state_path(state, "com.apple.symbolichotkeys").read_bytes() == original
        backup_root = Path(env["HOME"]) / "Library/Application Support/codyssey-init/macos-backups"
        assert list(backup_root.glob("*/hotkeys.missing")) == []


def run_verifier(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    verifier_env = env | {"CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST": "1"}
    return subprocess.run(("python3", str(ROOT / "verify-macos-setup.py")), env=verifier_env, text=True, capture_output=True, check=False)


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


def main() -> None:
    test_success_and_repeat()
    test_missing_chrome_preserves_entire_dock()
    test_export_and_write_failures_are_isolated_and_rolled_back()
    test_absent_domain_is_created_only_after_confirmed_absent()
    test_last_existing_domain_export_failure_is_not_absence()
    test_verifier_leaves_applied_state_on_success_and_restores_on_failure()
    test_verifier_retains_snapshot_when_restoration_fails()
    test_verifier_restores_after_keyboard_interrupt()
    print("macOS setup isolated tests: 8 passed")


if __name__ == "__main__":
    main()
