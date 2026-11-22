"""Read the selected Fusion guest display and send input over its localhost console."""

from contextlib import contextmanager
import re
import socket
import struct
import subprocess
import time


def read_frame(vmcli, vmx, recognizer, image, user):
    image.unlink(missing_ok=True)
    subprocess.run([vmcli, vmx, "MKS", "captureScreenshot", image], check=True, timeout=15)
    with image.open("rb") as frame:
        png = frame.read(24)
    if png[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR":
        raise ValueError("expected a Fusion PNG screenshot")
    size = struct.unpack(">II", png[16:])
    if min(size) <= 2:
        raise ValueError("the guest display is still starting")
    output = subprocess.check_output([recognizer, image, user], text=True, timeout=15, stderr=subprocess.DEVNULL)
    lines = [line.split("\t", 2) for line in output.splitlines()]
    return size, [(float(x), float(y), name.strip()) for x, y, name in lines if name.strip()]


def find_text(items, pattern, region):
    matches = [(x, y) for x, y, name in items if re.fullmatch(pattern, name) and region(x, y)]
    return matches[0] if len(matches) == 1 else None


def decline_app_reopen(items):
    # Background Apple services can ask to reopen during installation or first login.
    words = " ".join(text.lower() for _, _, text in items)
    if "opened versions" not in words or not ("differs from" in words or "are you sure you want to open it" in words):
        return None
    deny = find_text(items, r"Don['’]t Open", lambda x, y: 0.35 < x < 0.58 and 0.32 < y < 0.72)
    allow = find_text(items, "Open Anyway", lambda x, y: 0.53 < x < 0.78 and 0.38 < y < 0.72)
    if not allow:
        return None
    if deny and 0.06 < allow[0] - deny[0] < 0.17 and abs(allow[1] - deny[1]) < 0.025:
        return ("decline-app-reopen", deny, 1)
    # The two equal-width buttons are centered under the question. Vision can
    # miss the left label if another instance of the alert is partly behind it.
    question = find_text(
        items, r"Are you sure you want to open it[?:]?",
        lambda x, y: 0.04 < allow[0] - x < 0.09 and 0.08 < allow[1] - y < 0.18,
    )
    if not deny and question:
        return ("decline-app-reopen", (2 * question[0] - allow[0], allow[1]), 1)
    return None


def same_target(target, previous, size):
    if not target or not previous or target[0] != previous[0]:
        return False
    if target[1] is None or previous[1] is None:
        return target[1] is previous[1]
    return all(abs(first - second) * length <= 5 for first, second, length in zip(target[1], previous[1], size))


@contextmanager
def console(port, size):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
        with connection.makefile("rb") as reader:
            if reader.read(12) != b"RFB 003.008\n":
                raise ValueError("expected the Fusion RFB 3.8 console")
            connection.sendall(b"RFB 003.008\n")
            if 1 not in reader.read(int.from_bytes(reader.read(1), "big")):
                raise ValueError("expected an unauthenticated localhost console")
            connection.sendall(b"\x01")
            if reader.read(4) != bytes(4):
                raise ValueError("console handshake failed")
            connection.sendall(b"\x01")
            header = reader.read(24)
            if struct.unpack(">HH", header[:4]) != size:
                raise ValueError("guest display changed size")
            name_length = int.from_bytes(header[20:], "big")
            if name_length > 4096 or len(reader.read(name_length)) != name_length:
                raise ValueError("invalid Fusion console name")
        yield connection


def click(connection, size, point, count):
    x, y = (int(length * coordinate) for length, coordinate in zip(size, point))
    if not (0 <= x < size[0] and 0 <= y < size[1]):
        raise ValueError("target is outside the guest screen")
    connection.sendall(struct.pack(">BBHH", 5, 0, x, y))
    for _ in range(count):
        connection.sendall(struct.pack(">BBHH", 5, 1, x, y))
        time.sleep(0.06)
        connection.sendall(struct.pack(">BBHH", 5, 0, x, y))
        time.sleep(0.08)


def key(connection, keysym):
    for down in (1, 0):
        connection.sendall(struct.pack(">BBHI", 4, down, 0, keysym))
        time.sleep(0.035)


def type_text(connection, text):
    for character in text:
        key(connection, ord(character))
