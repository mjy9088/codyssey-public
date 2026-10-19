#!/usr/bin/env python3
"""Configure the dedicated Chrome profile, then close its temporary local CDP port."""
import base64
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import time
import urllib.parse
import urllib.request


class CDP:
    def __init__(self, url):
        address = urllib.parse.urlparse(url)
        if address.hostname not in ("127.0.0.1", "localhost"):
            raise RuntimeError("refusing a non-local browser control endpoint")
        self.socket = socket.create_connection((address.hostname, address.port), timeout=15)
        self.sequence = 0
        key = base64.b64encode(os.urandom(16)).decode()
        self.socket.sendall((f"GET {address.path} HTTP/1.1\r\nHost: {address.netloc}\r\n"
                             "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                             f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        header = b""
        while not header.endswith(b"\r\n\r\n"):
            header += self.exact(1)
            if len(header) > 8192:
                raise RuntimeError("invalid browser handshake")
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        if not header.startswith(b"HTTP/1.1 101 ") or accept not in header:
            raise RuntimeError("browser control handshake failed")

    def exact(self, size):
        data = b""
        while len(data) < size:
            chunk = self.socket.recv(size - len(data))
            if not chunk:
                raise RuntimeError("browser control connection closed")
            data += chunk
        return data

    def call(self, method, params):
        self.sequence += 1
        data = json.dumps({"id": self.sequence, "method": method, "params": params}).encode()
        if len(data) > 65535:
            raise RuntimeError("browser control request too large")
        length = len(data)
        header = bytes([129, 128 | length]) if length < 126 else bytes([129, 254]) + struct.pack("!H", length)
        mask = os.urandom(4)
        self.socket.sendall(header + mask + bytes(value ^ mask[index % 4] for index, value in enumerate(data)))
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            header = self.exact(2)
            size = header[1] & 127
            if size == 126:
                size = struct.unpack("!H", self.exact(2))[0]
            elif size == 127:
                size = struct.unpack("!Q", self.exact(8))[0]
            if size > 8 * 1024 * 1024 or header[1] & 128 or header[0] != 129:
                raise RuntimeError("unexpected browser control frame")
            result = json.loads(self.exact(size))
            if result.get("id") == self.sequence:
                if "error" in result:
                    raise RuntimeError(result["error"]["message"])
                return result["result"]
        raise RuntimeError("browser control response timed out")

    def evaluate(self, expression):
        result = self.call("Runtime.evaluate", {"expression": expression, "awaitPromise": True, "returnByValue": True})
        if "exceptionDetails" in result:
            raise RuntimeError("Chrome could not configure the extension")
        return result["result"].get("value")


def wait_stopped(pid):
    for _ in range(100):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    raise RuntimeError("Chrome did not close normally; no forced termination was attempted")


def configure(binary, profile, extension, extensions):
    # Only the dedicated profile may be restarted. Never terminate another Chrome
    # profile, grant OS permissions, or edit Chrome's protected preference hashes.
    lock = profile / "SingletonLock"
    if lock.is_symlink():
        owner = os.readlink(lock).rsplit("-", 1)[-1]
        if not owner.isdigit():
            raise RuntimeError("unrecognized Chrome profile lock")
        pid = int(owner)
        process = subprocess.run(["ps", "-p", str(pid), "-o", "args="], capture_output=True, text=True)
        if process.returncode == 0:
            if str(binary) not in process.stdout or f"--user-data-dir={profile}" not in process.stdout:
                raise RuntimeError("profile lock belongs to a different process")
            os.kill(pid, signal.SIGTERM)
            wait_stopped(pid)

    endpoint = profile / "DevToolsActivePort"
    endpoint.unlink(missing_ok=True)
    browser = subprocess.Popen([str(binary), f"--user-data-dir={profile}", f"--load-extension={extensions}",
                                "--remote-debugging-address=127.0.0.1", "--remote-debugging-port=0",
                                "--restore-last-session", "--no-first-run", "--no-default-browser-check",
                                "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    clients = []
    try:
        deadline = time.monotonic() + 30
        while not endpoint.exists():
            if browser.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("Chrome setup endpoint did not become ready")
            time.sleep(0.1)
        port = int(endpoint.read_text().splitlines()[0])
        base = f"http://127.0.0.1:{port}"

        def request(path, method="GET"):
            with urllib.request.urlopen(urllib.request.Request(base + path, method=method), timeout=15) as response:
                return json.load(response)

        manager = request("/json/new?" + urllib.parse.quote("chrome://extensions/", safe=""), "PUT")
        client = CDP(manager["webSocketDebuggerUrl"])
        clients.append(client)
        deadline = time.monotonic() + 15
        while not client.evaluate("typeof chrome !== 'undefined' && !!chrome.developerPrivate"):
            if time.monotonic() > deadline:
                raise RuntimeError("Chrome extension management API did not become ready")
            time.sleep(0.1)
        # This is Chrome's own per-profile Developer mode, not macOS Accessibility
        # or Screen Recording permission. Managed policy is respected by the API.
        result = client.evaluate("""new Promise(resolve => chrome.developerPrivate.updateProfileConfiguration(
          {inDeveloperMode:true}, () => resolve({error:chrome.runtime.lastError?.message || null})))""")
        if result.get("error"):
            raise RuntimeError(result["error"])
        identifier = hashlib.sha256(str(extension).encode()).hexdigest()[:32].translate(
            str.maketrans("0123456789abcdef", "abcdefghijklmnop"))
        item = json.dumps(identifier)
        result = client.evaluate(f"""new Promise(resolve => chrome.developerPrivate.getExtensionsInfo(
          {{includeDisabled:true,includeTerminated:true}}, rows => resolve(rows.find(x=>x.id==={item}))))""")
        if not result or result.get("name") != "Codyssey Tailnet":
            raise RuntimeError("the dedicated Tailnet extension was not loaded")
        if result.get("state") == "DISABLED":
            if not result.get("disableReasons", {}).get("unsupportedDeveloperExtension"):
                raise RuntimeError("Tailnet extension is disabled; refusing to override that choice or policy")
            outcome = client.evaluate(f"""new Promise(resolve => chrome.management.setEnabled({item},true,
              ()=>resolve({{error:chrome.runtime.lastError?.message || null}})))""")
            if outcome.get("error"):
                raise RuntimeError(outcome["error"])
        outcome = client.evaluate(f"""new Promise(resolve => chrome.developerPrivate.reload({item},
          {{failQuietly:true}}, ()=>resolve({{error:chrome.runtime.lastError?.message || null}})))""")
        if outcome.get("error"):
            raise RuntimeError(outcome["error"])
        # Chromium can temporarily disable a command-line unpacked extension on
        # reload even after Developer mode is enabled. Restore the enabled state
        # checked above through Chrome's API, without changing proxy opt-in.
        outcome = client.evaluate(f"""new Promise(resolve => chrome.management.setEnabled({item},true,
          ()=>resolve({{error:chrome.runtime.lastError?.message || null}})))""")
        if outcome.get("error"):
            raise RuntimeError(outcome["error"])
        popup = request("/json/new?" + urllib.parse.quote(f"chrome-extension://{identifier}/popup.html", safe=""), "PUT")
        popup_client = CDP(popup["webSocketDebuggerUrl"])
        clients.append(popup_client)
        deadline = time.monotonic() + 15
        while True:
            if not popup_client.evaluate("typeof chrome !== 'undefined' && !!chrome.runtime?.sendMessage"):
                if time.monotonic() > deadline:
                    state = popup_client.evaluate("({url:location.href,title:document.title})")
                    raise RuntimeError(f"Tailnet extension popup did not become ready: {state}")
                time.sleep(0.1)
                continue
            outcome = popup_client.evaluate("""new Promise(resolve => chrome.runtime.sendMessage(
              {type:'status'}, response=>resolve(response || {error:chrome.runtime.lastError?.message})))""")
            if outcome and "status" in outcome:
                if outcome["status"]["blocked"]:
                    raise RuntimeError("another extension or policy controls the proxy")
                break
            if time.monotonic() > deadline:
                raise RuntimeError("Tailnet extension did not become ready")
            time.sleep(0.2)
        for target in (popup, manager):
            # Close only the two setup tabs, retaining the user's restored tabs.
            with urllib.request.urlopen(base + "/json/close/" + target["id"], timeout=10):
                pass
        print("Portable Chrome Developer mode and Tailnet extension configured.")
    finally:
        for client in clients:
            client.socket.close()
        if browser.poll() is None:
            browser.terminate()
            try:
                browser.wait(timeout=15)
            except subprocess.TimeoutExpired:
                raise RuntimeError("Chrome setup is still closing; stop it normally before retrying")
        endpoint.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 5:
            raise RuntimeError("usage: configure-tailnet-browser.py BINARY PROFILE EXTENSION EXTENSION_LIST")
        configure(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve(), sys.argv[4])
    except (OSError, ValueError, RuntimeError, StopIteration) as error:
        print(f"tailnet-browser setup: {error or type(error).__name__}", file=sys.stderr)
        sys.exit(1)
