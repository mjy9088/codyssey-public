#!/usr/bin/env python3
"""Send real Fusion keyboard events at checkpoints published by the guest Terminal."""

from pathlib import Path
import re
import sys

from fusion_console import console, key, key_event, type_text


STAGES = (
    (b"A", "gks "),
    (b"B", None),
    (b"C", "abc"),
    (b"D", None),
    (b"E", "gks "),
)


def send_typing(client, text):
    if text is None:
        key_event(client, 0xffe3, 1)  # Control_L
        try:
            key(client, ord(" "))
        finally:
            key_event(client, 0xffe3, 0)
    else:
        type_text(client, text)
        key(client, 0xff0d)


def relay(stream, output, vmx, port):
    index = 0
    for line in stream:
        output.write(line)
        output.flush()
        marker = re.fullmatch(rb"Codyssey typing ([A-Z])", line.strip())
        if marker is None:
            continue
        if index >= len(STAGES) or marker[1] != STAGES[index][0]:
            raise RuntimeError("Unexpected guest typing checkpoint")
        log = vmx.with_name("vmware.log").read_text(errors="replace")
        if f"Started VNC server, listening at 127.0.0.1:{port}\n" not in log:
            raise RuntimeError("Fusion has not confirmed the loopback verification console")
        with console(port) as client:
            send_typing(client, STAGES[index][1])
        index += 1
    if index != len(STAGES):
        raise RuntimeError("Guest closed the connection before completing the typing checkpoints")


if __name__ == "__main__":
    try:
        vmx, port = sys.argv[1:]
        relay(sys.stdin.buffer, sys.stdout.buffer, Path(vmx), int(port))
    except (OSError, RuntimeError, ValueError) as error:
        sys.exit(f"Fusion typing check: {error}")
