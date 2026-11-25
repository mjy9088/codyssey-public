#!/usr/bin/env python3
"""Drive the English Sequoia installer over its private Fusion console."""

import argparse
from pathlib import Path
import re
import subprocess
import time

from fusion_console import click, console, decline_app_reopen, find_text, read_frame, same_target, type_text
from guest_credential import LAB_GUEST_PASSWORD

INSTALL_IDLE_TIMEOUT = 7200
BLOCKS_PER_GIB = 2 ** 21  # stat reports allocated space in 512-byte blocks.


def target_disk_blocks(bundle):
    blocks = 0
    for image in bundle.glob("Target*.vmdk"):
        try:
            blocks += image.stat().st_blocks
        except FileNotFoundError:
            continue
    return blocks


def installer_minutes_remaining(items):
    for _, _, text in items:
        match = re.fullmatch(
            r"(?:About )?(?:(\d+) hours?(?: and )? *)?(?:(\d+) minutes?)? remaining\.?",
            text, re.IGNORECASE,
        )
        if match and any(match.groups()):
            return 60 * int(match[1] or 0) + int(match[2] or 0)
    return None


def setup_action(items, account_filled):
    def button(pattern):
        return find_text(items, pattern, lambda _x, y: 0.59 < y < 0.97)

    words = " ".join(text.lower() for _, _, text in items)
    proceed = button(r"Continue|Get Started")
    decline = decline_app_reopen(items)
    if decline:
        return decline
    if "create a computer account" in words or "create a mac account" in words:
        if account_filled:
            return ("create-account", proceed, 1) if proceed and "creating account" not in words else None
        name = find_text(items, r"Full [Nn]ame:?", lambda x, y: 0.15 < x < 0.60 and 0.28 < y < 0.75)
        password = find_text(items, r"Password: new password", lambda x, y: 0.24 < x < 0.40 and 0.38 < y < 0.68)
        verify = find_text(items, r"verify", lambda x, y: 0.50 < x < 0.60 and 0.38 < y < 0.68)
        if name and password and verify and name[1] < password[1] and abs(password[1] - verify[1]) < 0.01:
            fields = ((0.46, name[1]), (0.40, password[1]), (0.63, verify[1]))
            return ("account-fields", fields, 1)
    if "terms and conditions" in words:
        confirm = find_text(items, "Agree", lambda x, y: 0.44 < x < 0.72 and 0.40 < y < 0.68)
        agree = confirm or button("Agree")
        return ("license", agree, 1) if agree else None
    skip = find_text(items, "Skip", lambda x, y: 0.45 < x < 0.70 and 0.45 < y < 0.76)
    if "are you sure you want to skip signing in with an apple account" in words:
        return ("apple-account-confirmation", skip, 1) if skip else None
    if skip and "apple account" in words and find_text(
        items, r"Don['’]t Skip", lambda x, y: 0.28 < x < skip[0] and abs(y - skip[1]) < 0.025,
    ):
        return ("apple-account-confirmation", skip, 1)
    if "transfer your data to this mac" in words and proceed:
        new_mac = find_text(items, r"(?:[•·] )?Set [Uu]p as [Nn]ew", lambda x, y: 0.24 < x < 0.70 and 0.45 < y < 0.80)
        if new_mac:
            return ("new-mac", (new_mac, proceed), 1)
    if "about analytics & privacy" in words and proceed:
        analytics = find_text(items, r"(?:[•·] )?Share Mac Analytics with Apple", lambda x, y: 0.35 < x < 0.60 and 0.40 < y < 0.54)
        if analytics:
            # A fresh Sequoia guest has this box selected by default.
            return ("disable-analytics", ((0.352, analytics[1]), proceed), 1)
    for title, choices in (
        ("transfer your information", r"Not Now|Set [Uu]p as [Nn]ew"),
        ("migration assistant", r"Not Now|Set [Uu]p as [Nn]ew"),
        ("apple account", r"Set Up Later"),
        ("accessibility", r"Not Now|Set Up Later"),
        ("screen time", r"Set Up Later|Not Now"),
        ("location services", r"Don.t Use|Not Now"),
        ("update mac automatically", r"Only Download Automatically"),
    ):
        if title in words:
            skip = button(choices) or find_text(items, choices, lambda x, y: 0.14 < x < 0.88 and 0.32 < y < 0.96)
            if skip:
                return (title, skip, 1)
    if "select your country or region" in words or "select your country" in words:
        region = find_text(items, "United States", lambda x, y: 0.15 < x < 0.85 and 0.20 < y < 0.85)
        if proceed and region:
            return ("region", (region, proceed), 1)
        if proceed:
            first_region = find_text(items, "Afghanistan", lambda x, y: 0.30 < x < 0.60 and 0.35 < y < 0.68)
            if first_region:
                return ("find-region", first_region, 1)
    if proceed and any(title in words for title in (
        "written and spoken languages", "data & privacy", "data and privacy",
        "enable location services", "select your time zone", "choose your look", "welcome to mac",
    )):
        return ("setup-continue", proceed, 1)
    return None


def installer_action(items):
    any_region = lambda _x, _y: True
    lower = lambda _x, y: y > 0.60
    words = " ".join(value.lower() for _, _, value in items)
    if "damaged" in words or "could not be verified" in words:
        raise RuntimeError("macOS reported that the installer could not be verified")
    if find_text(items, "Language", any_region) and find_text(items, "English", any_region):
        return ("language", find_text(items, "English", any_region), 1)
    if "software license agreement" in words or "license agreement" in words:
        modal = "i have read and agree" in words
        agree = find_text(items, "Agree", (lambda x, y: 0.45 < x < 0.70 and 0.46 < y < 0.68) if modal else lower)
        if agree:
            return ("license", agree, 1)
    if "disk where you want to install" in words or "select the disk" in words:
        disk = find_text(items, "Macintosh HD", any_region)
        install = find_text(items, r"Install|Continue", lower)
        if disk:
            return ("disk", disk, 1), ("install", install, 1)
    recovery = find_text(items, r"(?:Re)?[Ii]nstall macOS Sequoia", any_region)
    if recovery and ("disk utility" in words or "time machine" in words):
        return ("recovery", recovery, 2)
    if "macos sequoia" in words:
        proceed = find_text(items, "Continue", lower)
        if proceed:
            return ("continue", proceed, 1)
    return None


def drive_installer(vmx, vmcli, recognizer, output, port, accepted, setup_only=False):
    vmx = vmx.resolve(strict=True)
    last_progress = time.monotonic()
    disk_blocks = target_disk_blocks(vmx.parent)
    completed_actions = set()
    first_frame = True
    lowest_minutes_remaining = None
    before = None
    selected_disk = False
    installing = False
    setup = setup_only
    account_filled = False
    analytics_disabled = False
    desktop = False
    shutdown_requested = False
    print("Waiting for the macOS installer console.", flush=True)
    while True:
        if not setup and (blocks := target_disk_blocks(vmx.parent)) > disk_blocks:
            if blocks // BLOCKS_PER_GIB > disk_blocks // BLOCKS_PER_GIB:
                print(f"Guest target disk uses {blocks // BLOCKS_PER_GIB} GiB on the host.", flush=True)
            disk_blocks = blocks
            last_progress = time.monotonic()
        if time.monotonic() - last_progress >= INSTALL_IDLE_TIMEOUT:
            raise TimeoutError(
                f"No macOS installer progress for {INSTALL_IDLE_TIMEOUT}s. "
                f"Check the Fusion window and {output / 'installer-screen.txt'}."
            )
        try:
            size, items = read_frame(vmcli, vmx, recognizer, output / "installer.png", "vmuser", timeout=60)
        except (OSError, ValueError, subprocess.SubprocessError):
            if shutdown_requested:
                inventory = subprocess.check_output(
                    [vmcli.with_name("vmrun"), "-T", "fusion", "list"], text=True, timeout=15,
                )
                if guest_has_stopped(inventory, vmx):
                    print("Installed guest is shut down.", flush=True)
                    return
            before = None
            time.sleep(10)
            continue
        if first_frame:
            print("Fusion guest console is visible.", flush=True)
            first_frame = False
            last_progress = time.monotonic()
        if installing and not setup:
            remaining = installer_minutes_remaining(items)
            if remaining is not None and (lowest_minutes_remaining is None or remaining < lowest_minutes_remaining):
                lowest_minutes_remaining = remaining
                last_progress = time.monotonic()
        (output / "installer-screen.txt").write_text("\n".join(text for _, _, text in items) + "\n")
        words = " ".join(text.lower() for _, _, text in items)
        if installing and not setup and ("select your country" in words or "setup assistant" in words):
            print("macOS Setup Assistant is visible.", flush=True)
            setup = True
            last_progress = time.monotonic()
        if setup and account_filled and not desktop and find_text(items, "Finder", lambda x, y: x < 0.22 and y < 0.04):
            print("First Finder desktop is visible.", flush=True)
            desktop = True
            last_progress = time.monotonic()
        if desktop:
            stop = find_text(items, r"Shut Down(?:…|\.\.\.)?", lambda x, y: 0.02 < x < 0.72 and 0.10 < y < 0.90)
            if stop:
                action = ("shutdown", stop, 1)
            elif not shutdown_requested and find_text(items, "Finder", lambda x, y: x < 0.22 and y < 0.04):
                action = ("apple-menu", (0.027, 0.015), 1)
            else:
                action = None
        else:
            action = setup_action(items, account_filled) if setup else installer_action(items)
            if analytics_disabled and action and action[0] == "disable-analytics":
                action = ("setup-continue", action[1][1], 1)
        if installing and not setup and action and action[0] == "recovery":
            raise RuntimeError("The guest returned to Recovery after installation. Boot the staged target disk.")
        if action and isinstance(action[0], tuple):
            action = action[int(selected_disk)]
            if action[1] is None:
                action = None
        batch = action and isinstance(action[1], tuple) and isinstance(action[1][0], tuple)
        if (batch and action == before) or (not batch and same_target(action, before, size)):
            label, point, count = action
            if label == "license" and not accepted:
                raise RuntimeError("Authorize the macOS license on the host with --accept-license.")
            log = vmx.with_name("vmware.log").read_text(errors="replace")
            if f"Started VNC server, listening at 127.0.0.1:{port}\n" not in log:
                raise RuntimeError("Fusion has not confirmed the loopback console")
            with console(port, size) as client:
                if label == "account-fields":
                    for field, value in zip(point, ("vmuser", LAB_GUEST_PASSWORD, LAB_GUEST_PASSWORD)):
                        click(client, size, field, 1)
                        type_text(client, value)
                    account_filled = True
                elif batch:
                    for button in point:
                        click(client, size, button, 1)
                elif label == "find-region":
                    click(client, size, point, 1)
                    type_text(client, "United States")
                else:
                    click(client, size, point, count)
                if label == "language":
                    # The Recovery language picker uses an unlabeled arrow.
                    click(client, size, (0.857, 0.853), 1)
            # Several distinct Setup Assistant screens share the Continue button.
            progress = label
            if label == "setup-continue":
                progress = (label, frozenset(text.casefold() for _, _, text in items))
            if progress not in completed_actions:
                completed_actions.add(progress)
                print(f"Installer screen: {label}", flush=True)
                last_progress = time.monotonic()
            if label == "disk":
                selected_disk = True
            elif label == "install" or (label == "continue" and selected_disk):
                installing = True
            elif label == "shutdown":
                shutdown_requested = True
            elif label == "disable-analytics":
                analytics_disabled = True
            before = None
        else:
            before = action
        time.sleep(8 if action else 30)


def guest_has_stopped(inventory, vmx):
    header, *paths = inventory.strip().splitlines() or [""]
    count = re.fullmatch(r"Total running VMs: (\d+)", header)
    if not count or int(count[1]) != len(paths):
        return False
    running = [Path(path) for path in paths]
    if any(not path.is_absolute() or path.suffix.lower() != ".vmx" for path in running):
        return False
    try:
        return not any(path.samefile(vmx) for path in running)
    except OSError:
        return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vmx", type=Path)
    parser.add_argument("vmcli", type=Path)
    parser.add_argument("recognizer", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("port", type=int)
    parser.add_argument("--accept-license", action="store_true")
    parser.add_argument("--setup-only", action="store_true")
    args = parser.parse_args()
    try:
        drive_installer(args.vmx, args.vmcli, args.recognizer, args.output, args.port, args.accept_license, args.setup_only)
    except (OSError, RuntimeError, ValueError) as error:
        parser.exit(1, f"{error}\n")
