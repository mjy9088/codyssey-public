#!/usr/bin/env python3
"""Open the setup disc using the selected Fusion VM's screenshot and localhost console."""

from pathlib import Path
import re
import struct
import subprocess
import sys
import time

from fusion_console import click, console, decline_app_reopen, find_text, key, read_frame, same_target, type_text
from guest_credential import guest_password


def focus_finder(connection):
    # macOS Option-Command-Space opens a Finder search window.
    keys = (0xffe9, 0xffeb, 0x20)
    for down, sequence in ((1, keys), (0, reversed(keys))):
        for key in sequence:
            connection.sendall(struct.pack(">BBHI", 4, down, 0, key))
            time.sleep(0.15)

def type_password(connection, password):
    type_text(connection, password)
    key(connection, 0xff0d)


def can_focus_finder(items):
    labels = {word for x, y, line in items if x < 0.65 and y < 0.04 for word in line.split()}
    return {"Edit", "Window", "Help"} <= labels


def approval_target(items, password_available, prompt_id, user, handled):
    # Require dialog-specific text as well as the action button.
    center = lambda x, y: 0.15 < x < 0.88 and 0.12 < y < 0.90
    terminal = find_text(items, "Terminal", lambda x, y: x < 0.22 and y < 0.04)
    prompt = any(f"Codyssey {prompt_id} password:" in name for _, _, name in items)
    if password_available and "password" not in handled and terminal and prompt:
        return "password", None, 0
    labels = " ".join(name.lower() for x, y, name in items if center(x, y))
    vmware_context = "vmware, inc." in labels or "installer: package name is vmware tools" in labels
    if "system extension blocked" in labels and vmware_context:
        if "vmware-settings" in handled:
            okay = find_text(items, "OK", center)
            if okay:
                return "vmware-dismiss", okay, 1
        settings = find_text(items, "Open System Settings", center)
        if settings:
            return "vmware-settings", settings, 1
    if "vmware-extension" in handled and "modify settings" in labels:
        account = find_text(items, re.escape(user), center)
        field = find_text(items, "Password", center)
        if account and field and 0 < field[1] - account[1] < 0.10:
            return "vmware-auth", field, 1
        if field:
            x_field, y_field = field
            heading = find_text(
                items, r"Privacy & Security is trying to modify(?: your system settings\.)?",
                lambda x, y: abs(x - x_field) < 0.17 and 0.04 < y_field - y < 0.22,
            )
            instructions = find_text(
                items, r"Enter your password to allow this\.?",
                lambda x, y: abs(x - x_field) < 0.17 and 0 < y_field - y < 0.13,
            )
            modify = find_text(
                items, "Modify Settings",
                lambda x, y: abs(x - x_field) < 0.22 and 0 < y - y_field < 0.18,
            )
            if heading and instructions and modify and heading[1] < instructions[1]:
                return "vmware-auth", field, 1
    if "vmware-extension" in handled and "a restart is required" in labels and "system extensions" in labels:
        later = find_text(items, "Not Now", center)
        if later:
            return "vmware-restart-deferred", later, 1
    if "terminal" in labels and "would like to" in labels and "administer your computer" in labels:
        prompt = find_text(items, r"administer your computer\.", center)
        if prompt:
            allow = find_text(
                items, "Allow", lambda x, y: abs(x - prompt[0]) < 0.25 and 0 < y - prompt[1] < 0.20,
            )
            if allow:
                return "terminal-admin", allow, 1
    if "vmware, inc." in labels and "system software" in labels and "blocked" in labels:
        allow = find_text(items, "Allow", center)
        if allow:
            return "vmware-extension", allow, 1
    return None


def open_setup(vmcli, vmx, recognizer, image, port, user, prompt_id):
    # Leave room for the first login and queued application-reopen prompts.
    deadline = time.monotonic() + 420
    previous = None
    requested_finder = False
    password = guest_password()
    opened = False
    handled = set()
    ready_frames = 0
    while time.monotonic() < deadline:
        guest_ready = False
        if opened:
            vmrun = Path(vmcli).with_name("vmrun")
            state = subprocess.run(
                [vmrun, "-T", "fusion", "readVariable", vmx, "guestVar", "codyssey.setup-state"],
                capture_output=True, text=True, timeout=10,
            )
            guest_ready = state.returncode == 0 and state.stdout.strip() == "ready"
        try:
            size, items = read_frame(vmcli, vmx, recognizer, image, user)
        except (OSError, ValueError, subprocess.SubprocessError):
            previous = None
        else:
            image.with_suffix(".txt").write_text("\n".join(text for _, _, text in items) + "\n")
            target = decline_app_reopen(items)
            if target:
                ready_frames = 0
            elif opened:
                target = approval_target(items, password is not None, prompt_id, user, handled)
                if target:
                    repeatable = target[0] in ("terminal-admin", "vmware-dismiss", "vmware-restart-deferred")
                    if password is None or (target[0] in handled and not repeatable):
                        target = None
                if guest_ready and not target:
                    ready_frames += 1
                    if ready_frames == 2:
                        print("Guest setup reported Remote Login ready.", flush=True)
                        return
                else:
                    ready_frames = 0
            elif password and "login" not in handled:
                login = find_text(items, "Enter Password", lambda x, y: 0.30 < x < 0.70 and 0.55 < y < 0.98)
                account = find_text(items, re.escape(user), lambda x, y: 0.30 < x < 0.70 and 0.5 < y < 0.96)
                if login and account and 0 < login[1] - account[1] < 0.12:
                    target = ("login", login, 1)
            if not opened and not target and find_text(items, "Finder", lambda x, y: x < 0.22 and y < 0.04):
                setup = find_text(items, r"Start Setup(?:\.command)?", lambda x, y: 0.18 < x < 0.97 and 0.08 < y < 0.87)
                tools = find_text(items, r"VMware Tools(?:\.pkg)?", lambda x, y: 0.18 < x < 0.97 and 0.08 < y < 0.87)
                volume = find_text(items, r"Codyssey(?: \d+)?", lambda x, y: 0.22 < x < 0.97 and 0.14 < y < 0.88)
                computer = find_text(items, r"(?:[•·] )?Computer", lambda x, y: x < 0.45 and 0.07 < y < 0.64)
                go = find_text(items, "Go", lambda x, y: 0.12 < x < 0.38 and y < 0.04)
                if setup and tools:
                    target = ("setup", setup, 2)
                elif volume:
                    target = ("volume", volume, 2)
                elif computer:
                    target = ("computer", computer, 1)
                elif go:
                    target = ("go", go, 1)
            elif not opened and not target and not requested_finder and can_focus_finder(items):
                target = ("finder", None, 0)
            if same_target(target, previous, size):
                label, point, count = target
                log = Path(vmx).with_name("vmware.log").read_text(errors="replace")
                if f"Started VNC server, listening at 127.0.0.1:{port}\n" not in log:
                    raise ValueError("Fusion has not confirmed the loopback VNC listener")
                with console(port, size) as connection:
                    if label == "finder":
                        focus_finder(connection)
                        requested_finder = True
                    elif label == "password":
                        type_password(connection, password)
                    elif label in ("login", "vmware-auth"):
                        click(connection, size, point, count)
                        type_password(connection, password)
                    else:
                        click(connection, size, point, count)
                if label == "setup":
                    print("Opened Start Setup.command in the guest.", flush=True)
                    opened = True
                    deadline = time.monotonic() + 300
                elif opened or label in ("login", "decline-app-reopen"):
                    handled.add(label)
                    print("Handled the guest " + label + " prompt.", flush=True)
                previous = None
            else:
                previous = target
        time.sleep(6)
    if not opened:
        raise TimeoutError("the Finder setup file could not be confirmed on screen")
    # Step 05 owns the readiness decision and can verify it over pinned SSH.
    print("Setup disc opened. Step 05 will verify Remote Login over SSH.", flush=True)


if __name__ == "__main__":
    vmcli, vmx, recognizer, image, port, user, prompt_id = sys.argv[1:]
    try:
        open_setup(vmcli, vmx, recognizer, Path(image), int(port), user, prompt_id)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"Could not open the guest setup file automatically: {error}")
