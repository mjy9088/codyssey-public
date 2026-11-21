#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==13.0.0"]
# ///
"""Watch a running Fusion guest for the macOS installer screen."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

from PIL import Image


def classify_frame(nonblack_fraction, apple_pixel, progress_pixels):
    if nonblack_fraction > 0.15:
        return "menu-candidate", {}
    if apple_pixel is not None and apple_pixel > 200:
        filled = sum(pixel >= 120 for pixel in progress_pixels)
        return "booting", {"progress_percent": round(filled * 100 / len(progress_pixels))}
    return "waiting", {}


def inspect_frame(path):
    with Image.open(path) as image:
        gray = image.convert("L")
    nonblack_fraction = sum(gray.histogram()[24:]) / (gray.width * gray.height)
    apple_pixel = None
    progress_pixels = ()
    if gray.size == (1024, 768):
        apple_pixel = gray.getpixel((510, 400))
        progress_pixels = tuple(gray.getpixel((x, 687)) for x in range(395, 629))
    return classify_frame(nonblack_fraction, apple_pixel, progress_pixels)


def inventory_paths(stdout):
    lines = stdout.strip().splitlines()
    if not lines:
        return None
    header = re.fullmatch(r"Total running VMs: (\d+)", lines[0])
    paths = [Path(line) for line in lines[1:]]
    if not header or int(header[1]) != len(paths):
        return None
    if any(not path.is_absolute() or path.suffix.lower() != ".vmx" for path in paths):
        return None
    try:
        return {path.resolve(strict=True) for path in paths}
    except (OSError, RuntimeError):
        return None


def watch(vmx, fusion_library, output, interval, timeout, monitor=False):
    vmcli = fusion_library / "vmcli"
    vmrun = fusion_library / "vmrun"
    screenshot = output / "screen.png"
    started = time.monotonic()
    deadline = started + timeout

    with tempfile.TemporaryDirectory(prefix=".watch-", dir=output) as directory:
        staging = Path(directory)

        def publish(state, **details):
            status = {
                "state": state,
                "elapsed_seconds": round(time.monotonic() - started),
                **details,
            }
            pending = staging / "status.json"
            pending.write_text(json.dumps(status) + "\n")
            pending.chmod(0o600)
            pending.replace(output / "status.json")
            print(json.dumps(status), flush=True)

        while (remaining := deadline - time.monotonic()) > 0:
            pending = staging / "screen.png"
            try:
                subprocess.run(
                    [vmcli, vmx, "MKS", "captureScreenshot", pending],
                    check=True, capture_output=True, timeout=min(15, remaining),
                )
                state, details = inspect_frame(pending)
            except (OSError, subprocess.SubprocessError) as error:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                try:
                    inventory = subprocess.run(
                        [vmrun, "-T", "fusion", "list"], check=True,
                        encoding="utf-8", capture_output=True, timeout=min(15, remaining),
                    )
                except (OSError, subprocess.SubprocessError, UnicodeDecodeError):
                    inventory = None
                running = inventory_paths(inventory.stdout) if inventory is not None else None
                if running is not None and vmx not in running:
                    publish("not-listed")
                    return 1
                publish("capture-unavailable", error=type(error).__name__)
            else:
                pending.chmod(0o600)
                pending.replace(screenshot)
                publish(state, screenshot=str(screenshot), **details)
                if state == "menu-candidate" and not monitor:
                    return 0

            if (remaining := deadline - time.monotonic()) > 0:
                time.sleep(min(interval, remaining))

        publish("timeout")
        return 124


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vmx", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--fusion-library", type=Path, default=Path(
        "/Applications/VMware Fusion.app/Contents/Library"
    ))
    parser.add_argument("--interval", type=int, default=60, help="seconds between captures")
    parser.add_argument("--timeout", type=int, default=3600, help="overall limit in seconds")
    parser.add_argument("--monitor", action="store_true",
                        help="continue capturing after the first installer screen")
    args = parser.parse_args()
    if args.interval <= 0 or args.timeout <= 0:
        parser.error("interval and timeout must be positive")
    vmx = args.vmx.resolve()
    if vmx.suffix.lower() != ".vmx" or not vmx.is_file():
        parser.error("--vmx must point to an existing VMX file")
    if not all((args.fusion_library / name).is_file() for name in ("vmcli", "vmrun")):
        parser.error("--fusion-library must contain vmcli and vmrun")
    args.output_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        return watch(vmx, args.fusion_library.resolve(), args.output_dir.resolve(),
                     args.interval, args.timeout, monitor=args.monitor)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
