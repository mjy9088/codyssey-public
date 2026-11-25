"""Serve a disposable copy of the public portfolio for local preview and tests."""

import os
import signal
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from shutil import copy2, copytree
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent.parent

def stop(_signal: int, _frame: object) -> None:
    raise KeyboardInterrupt


def ignore_local_files(folder: str, names: list[str]) -> list[str]:
    return [
        name
        for name in names
        if name.startswith(".") or name.endswith((".pem", ".key")) or Path(folder, name).is_symlink()
    ]


signal.signal(signal.SIGTERM, stop)
with TemporaryDirectory(prefix="portfolio-") as directory:
    site = Path(directory)
    copy2(root / "index.html", site)
    for folder in ("css", "images", "js"):
        copytree(root / folder, site / folder, ignore=ignore_local_files)
    handler = partial(SimpleHTTPRequestHandler, directory=directory)
    with ThreadingHTTPServer((os.getenv("COURSEWORK_LISTEN", "127.0.0.1"), 8000), handler) as server:
        print("Portfolio preview: http://127.0.0.1:8000", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
