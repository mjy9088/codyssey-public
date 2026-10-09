#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Final, TypeAlias

PlistValue: TypeAlias = str | bytes | int | float | bool | list["PlistValue"] | dict[str, "PlistValue"]
DOMAINS: Final = ("NSGlobalDomain", "com.apple.dock", "com.apple.HIToolbox", "com.apple.symbolichotkeys")
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
KOREAN: Final[dict[str, PlistValue]] = {
    "InputSourceKind": "Input Mode",
    "Bundle ID": "com.apple.inputmethod.Korean",
    "Input Mode": "com.apple.inputmethod.Korean.2SetKorean",
}


@dataclass(frozen=True, slots=True)
class DomainSnapshot:
    domain: str
    path: Path
    existed: bool


@dataclass(frozen=True, slots=True)
class VerificationError(RuntimeError):
    reason: str

    def __str__(self) -> str:
        return self.reason


def run(arguments: tuple[str, ...], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, check=check, text=True, capture_output=True)


def defaults() -> str:
    return os.environ.get("DEFAULTS_BIN", "defaults")


def domain_exists(domain: str) -> bool:
    result = run((defaults(), "domains"), check=False)
    if result.returncode != 0:
        raise VerificationError("defaults domains could not establish domain absence")
    return domain in {item.strip() for item in result.stdout.split(",")}


def snapshot(domain: str, directory: Path) -> DomainSnapshot:
    path = directory / f"{domain.replace('/', '_')}.plist"
    result = run((defaults(), "export", domain, str(path)), check=False)
    if result.returncode == 0:
        path.chmod(0o600)
        return DomainSnapshot(domain=domain, path=path, existed=True)
    path.unlink(missing_ok=True)
    if domain == "NSGlobalDomain" or domain_exists(domain):
        raise VerificationError(f"could not safely snapshot {domain}")
    return DomainSnapshot(domain=domain, path=path, existed=False)


def load(path: Path) -> dict[str, PlistValue]:
    with path.open("rb") as stream:
        value: PlistValue = plistlib.load(stream)
    if not isinstance(value, dict):
        raise VerificationError(f"{path.name} is not a plist dictionary")
    return value


def save(path: Path, value: dict[str, PlistValue]) -> None:
    with path.open("wb") as stream:
        plistlib.dump(value, stream, sort_keys=True)
    path.chmod(0o600)


def export(domain: str, directory: Path, label: str) -> dict[str, PlistValue]:
    path = directory / f"{label}-{domain.replace('/', '_')}.plist"
    run((defaults(), "export", domain, str(path)))
    path.chmod(0o600)
    return load(path)


def dictionaries(value: PlistValue, label: str) -> list[dict[str, PlistValue]]:
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise VerificationError(f"{label} is not an array of dictionaries")
    return [item for item in value if isinstance(item, dict)]


def prepare_fixture(baseline: tuple[DomainSnapshot, ...], directory: Path) -> tuple[list[dict[str, PlistValue]], dict[str, PlistValue]]:
    by_domain = {item.domain: item for item in baseline}
    if not all(item.existed for item in baseline):
        raise VerificationError("all live preference domains must exist before destructive verification")

    global_values = load(by_domain["NSGlobalDomain"].path)
    global_values.update({key: True for key in TEXT_KEYS})
    dock_values = load(by_domain["com.apple.dock"].path)
    dock_values["persistent-apps"] = []
    dock_values["persistent-others"] = []

    input_values = load(by_domain["com.apple.HIToolbox"].path)
    sources = dictionaries(input_values.get("AppleEnabledInputSources", []), "AppleEnabledInputSources")
    latin_sources = [source for source in sources if source.get("InputSourceKind") == "Keyboard Layout" and "Korean" not in str(source.get("KeyboardLayout Name", ""))]
    if not latin_sources:
        raise VerificationError("baseline has no Latin Keyboard Layout to preserve")
    unrelated_sources = [
        source
        for source in sources
        if not (
            source.get("InputSourceKind") == KOREAN["InputSourceKind"]
            and source.get("Bundle ID") == KOREAN["Bundle ID"]
            and source.get("Input Mode") == KOREAN["Input Mode"]
        )
    ]
    input_values["AppleEnabledInputSources"] = unrelated_sources

    hotkey_values = load(by_domain["com.apple.symbolichotkeys"].path)
    raw_hotkeys = hotkey_values.get("AppleSymbolicHotKeys", {})
    if not isinstance(raw_hotkeys, dict):
        raise VerificationError("AppleSymbolicHotKeys is not a dictionary")
    unrelated_hotkeys = {key: value for key, value in raw_hotkeys.items() if key not in {"60", "61"}}
    hotkey_values["AppleSymbolicHotKeys"] = unrelated_hotkeys

    fixtures = {
        "NSGlobalDomain": global_values,
        "com.apple.dock": dock_values,
        "com.apple.HIToolbox": input_values,
        "com.apple.symbolichotkeys": hotkey_values,
    }
    for domain, values in fixtures.items():
        path = directory / f"fixture-{domain}.plist"
        save(path, values)
        run((defaults(), "import", domain, str(path)))
    return unrelated_sources, unrelated_hotkeys


def verify_preferences(directory: Path, unrelated_sources: list[dict[str, PlistValue]], unrelated_hotkeys: dict[str, PlistValue]) -> tuple[dict[str, PlistValue], ...]:
    values = tuple(export(domain, directory, "applied") for domain in DOMAINS)
    global_values, dock_values, input_values, hotkey_values = values
    if not all(global_values.get(key) is False for key in TEXT_KEYS):
        raise VerificationError("not all text automation preferences are false")

    terminal = Path(os.environ.get("CODYSSEY_SYSTEM_APPLICATIONS_DIR", "/System/Applications")) / "Utilities/Terminal.app"
    primary_chrome = Path(os.environ.get("CODYSSEY_APPLICATIONS_DIR", "/Applications")) / "Google Chrome.app"
    chrome = primary_chrome if primary_chrome.is_dir() else Path.home() / "Applications/Google Chrome.app"
    expected_urls = [f"file://{str(terminal).replace(' ', '%20')}/", f"file://{str(chrome).replace(' ', '%20')}/"]
    apps = dictionaries(dock_values.get("persistent-apps", []), "persistent-apps")
    urls: list[PlistValue] = []
    for app in apps:
        tile_data = app.get("tile-data")
        if not isinstance(tile_data, dict) or not isinstance(tile_data.get("file-data"), dict):
            raise VerificationError("Dock entry has an invalid plist shape")
        urls.append(tile_data["file-data"].get("_CFURLString"))
    if urls != expected_urls or dock_values.get("persistent-others") != [] or dock_values.get("show-recents") is not False or dock_values.get("static-only") is not False:
        raise VerificationError("Dock preferences do not exactly match the requested state")

    sources = dictionaries(input_values.get("AppleEnabledInputSources", []), "AppleEnabledInputSources")
    if sources != [*unrelated_sources, KOREAN]:
        raise VerificationError("input sources were not preserved with one exact Korean mode")
    hotkeys = hotkey_values.get("AppleSymbolicHotKeys")
    if not isinstance(hotkeys, dict):
        raise VerificationError("AppleSymbolicHotKeys is not a dictionary")
    expected_60 = {"enabled": True, "value": {"type": "standard", "parameters": [32, 49, 262144]}}
    expected_61 = {"enabled": True, "value": {"type": "standard", "parameters": [32, 49, 786432]}}
    if {key: value for key, value in hotkeys.items() if key not in {"60", "61"}} != unrelated_hotkeys or hotkeys.get("60") != expected_60 or hotkeys.get("61") != expected_61:
        raise VerificationError("symbolic hotkeys do not preserve unrelated typed entries")
    return values


def restore(baseline: tuple[DomainSnapshot, ...]) -> list[str]:
    failures: list[str] = []
    for item in baseline:
        try:
            if item.existed:
                result = run((defaults(), "import", item.domain, str(item.path)), check=False)
            else:
                result = run((defaults(), "delete", item.domain), check=False)
                if result.returncode != 0:
                    domains = run((defaults(), "domains"), check=False)
                    if domains.returncode == 0 and item.domain not in {entry.strip() for entry in domains.stdout.split(",")}:
                        continue
        except OSError:
            failures.append(item.domain)
            continue
        if result.returncode != 0:
            failures.append(item.domain)
    return failures


def main() -> None:
    if os.environ.get("CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST") != "1":
        raise VerificationError("set CODYSSEY_ALLOW_DESTRUCTIVE_MACOS_TEST=1 after reading the warning")
    uname = os.environ.get("UNAME_BIN", "uname")
    if run((uname, "-s")).stdout.strip() != "Darwin":
        raise VerificationError("live macOS verification requires Darwin")

    os.umask(0o077)
    root = Path(__file__).resolve().parent
    snapshot_root = Path(tempfile.mkdtemp(prefix="macos-live-verify-"))
    snapshot_root.chmod(0o700)
    baseline: tuple[DomainSnapshot, ...] = ()
    preferences_mutated = False
    try:
        baseline = tuple(snapshot(domain, snapshot_root) for domain in DOMAINS)
        preferences_mutated = True
        unrelated_sources, unrelated_hotkeys = prepare_fixture(baseline, snapshot_root)
        run(("bash", str(root / "macos-setup.sh")))
        first = verify_preferences(snapshot_root, unrelated_sources, unrelated_hotkeys)
        run(("bash", str(root / "macos-setup.sh")))
        second = verify_preferences(snapshot_root, unrelated_sources, unrelated_hotkeys)
        if first != second:
            raise VerificationError("second application changed preferences")
    except BaseException:  # noqa: BROAD_EXCEPT_OK -- cleanup boundary must include interrupts, then rethrow.
        failures = restore(baseline) if preferences_mutated else []
        if failures:
            print(f"restoration failed for {', '.join(failures)}; backup retained at {snapshot_root}", file=sys.stderr)
        else:
            shutil.rmtree(snapshot_root)
        raise
    shutil.rmtree(snapshot_root)


if __name__ == "__main__":
    main()
