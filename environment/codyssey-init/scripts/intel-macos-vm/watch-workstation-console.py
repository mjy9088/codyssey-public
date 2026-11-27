#!/usr/bin/env python3
"""Handle the disposable VM login and a known input-method approval during verification."""

from pathlib import Path
import re
import subprocess
import sys
import time

from fusion_console import click, console, decline_app_reopen, find_text, key, read_frame, same_target, type_text
from guest_credential import guest_password


def action_for(items, user, signed_in):
    decline = decline_app_reopen(items)
    if decline:
        return decline
    if not signed_in:
        account = find_text(items, re.escape(user), lambda x, y: 0.30 < x < 0.70 and 0.5 < y < 0.96)
        password = find_text(items, "Enter Password", lambda x, y: 0.30 < x < 0.70 and 0.55 < y < 0.98)
        if account and password and 0 < password[1] - account[1] < 0.12:
            return ("login", password, 1)
    # The Swift activation helper is the requester shown by Sequoia.
    request = find_text(
        items, r'Allow ["“]swift-frontend["”] to enable.*',
        lambda x, y: 0.25 < x < 0.78 and 0.30 < y < 0.72,
    )
    if request:
        _, top = request
        message = any(
            0.25 < x < 0.78 and top < y < top + 0.15
            and re.match(r"(?:The developer [oi]f the input source|able to access anything you type with)\b", text)
            for x, y, text in items
        )
        deny = find_text(
            items, r"Don['’]t Allow",
            lambda x, y: 0.25 < x < 0.65 and top < y < min(top + 0.32, 0.86),
        )
        button = find_text(
            items, "Allow",
            lambda x, y: bool(deny and deny[0] < x < 0.78 and abs(y - deny[1]) < 0.025),
        )
        if message and button:
            return ("gureum", button, 1)
    return None


def watch(vmcli, vmx, recognizer, port, user, image):
    password = guest_password()
    # Allow for guest boot and staging before the one-hour workstation check.
    deadline = time.monotonic() + 4800
    signed_in = False
    previous = None
    while time.monotonic() < deadline:
        try:
            size, items = read_frame(vmcli, vmx, recognizer, image, user)
        except (OSError, ValueError, subprocess.SubprocessError):
            previous = None
            time.sleep(10)
            continue
        target = action_for(items, user, signed_in or password is None)
        if same_target(target, previous, size):
            log = vmx.with_name("vmware.log").read_text(errors="replace")
            if f"Started VNC server, listening at 127.0.0.1:{port}\n" not in log:
                raise RuntimeError("Fusion has not confirmed the loopback verification console")
            name, point, count = target
            with console(port, size) as client:
                click(client, size, point, count)
                if name == "login":
                    type_text(client, password)
                    key(client, 0xff0d)
                    signed_in = True
            print(f"Verification console handled {name}.", flush=True)
            previous = None
        else:
            previous = target
        time.sleep(6)


if __name__ == "__main__":
    vmcli, vmx, recognizer, port, user, image = sys.argv[1:]
    watch(vmcli, Path(vmx), recognizer, int(port), user, Path(image))
