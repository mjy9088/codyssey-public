#!/usr/bin/env python3
"""Inspect installed applications and execute CLI version queries without an engine."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys


def bundle(candidates, identifiers):
    for path in candidates:
        info = path / "Contents/Info.plist"
        if not info.is_file():
            continue
        with info.open("rb") as stream:
            values = plistlib.load(stream)
        if values.get("CFBundleIdentifier") not in identifiers:
            raise RuntimeError("Unexpected application identity: " + str(path))
        return path, values
    raise RuntimeError("Required application is missing: " + str(candidates[-1].name))


def inspect(home, applications=Path("/Applications"), input_methods=Path("/Library/Input Methods"), system=Path("/System/Applications")):
    orb, _ = bundle([applications / "OrbStack.app", home / "Applications/OrbStack.app"], {"dev.kdrag0n.MacVirt", "dev.kdrag0n.OrbStack"})
    gureum, info = bundle([home / "Library/Input Methods/Gureum.app", input_methods / "Gureum.app"], {"org.youknowone.inputmethod.Gureum"})
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or "/" in executable:
        raise RuntimeError("Invalid Gureum executable name")
    gureum_binary = gureum / "Contents/MacOS" / executable
    if not gureum_binary.is_file() or not os.access(gureum_binary, os.X_OK):
        raise RuntimeError("Gureum executable is missing or not executable")
    bundle([applications / "Google Chrome.app", home / "Applications/Google Chrome.app"], {"com.google.Chrome"})
    bundle([applications / "iTerm.app", home / "Applications/iTerm.app"], {"com.googlecode.iterm2"})
    if not (system / "Utilities/Terminal.app").is_dir():
        raise RuntimeError("Terminal is missing")
    binaries = [orb / "Contents/MacOS/bin/orb"]
    binaries += [orb / "Contents/MacOS/xbin" / name for name in ("docker", "docker-compose", "docker-buildx")]
    for binary in binaries:
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise RuntimeError("Bundled tool is missing or not executable: " + str(binary))
    return binaries[1:]


def main(workstation=False):
    if sys.platform != "darwin" or os.getuid() == 0:
        raise RuntimeError("Run as the macOS guest desktop user")
    binaries = inspect(Path.home())
    # A fresh image must reach the missing-Docker startup path. Do not query an
    # engine or launch OrbStack while checking it.
    if not workstation:
        probe = subprocess.run(["/bin/zsh", "-ic", "command -v docker"], capture_output=True)
        if probe.returncode == 0:
            raise RuntimeError("Docker is already on the login PATH; use a fresh base")
    for binary, argument in zip(binaries, ("--version", "version", "version")):
        result = subprocess.run([str(binary), argument], capture_output=True, text=True, timeout=200)
        if result.returncode:
            raise RuntimeError("Bundled CLI version query failed: " + binary.name + ": " + result.stderr[-400:])
    subprocess.run(["/usr/bin/swift", "--version"], check=True, capture_output=True, timeout=300)
    path_check = "" if workstation else ", and missing Docker PATH"
    print("PASS: installed app identities, Gureum executable, bundled CLI execution, Swift"
          f"{path_check}; no engine started.")


if __name__ == "__main__":
    try:
        if sys.argv[1:] not in ([], ["--workstation"]):
            raise RuntimeError("Usage: check-preinstalled-apps.py [--workstation]")
        main(workstation=sys.argv[1:] == ["--workstation"])
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("Preinstalled image check: " + str(error), file=sys.stderr)
        sys.exit(1)
