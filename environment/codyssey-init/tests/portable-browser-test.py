"""Exercise portable browser downloads and launches using synthetic tools only."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = b"publishable synthetic browser archive"

FAKE_TOOL = r'''
import hashlib, json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["BROWSER_TEST_LOG"], "a") as log:
    log.write(json.dumps([tool, *args]) + "\n")
if tool == "uname":
    print(os.environ.get("FAKE_OS", "Darwin") if args[0] == "-s" else os.environ.get("FAKE_MACHINE", "x86_64"))
elif tool == "curl":
    if os.environ.get("FAIL_DOWNLOAD"): sys.exit(22)
    pathlib.Path(args[args.index("-o") + 1]).write_bytes(b"publishable synthetic browser archive")
elif tool == "shasum":
    digest = hashlib.sha256(pathlib.Path(args[-1]).read_bytes()).hexdigest()
    print(("0" * 64 if os.environ.get("BAD_CHECKSUM") else digest) + "  " + args[-1])
elif tool == "ditto":
    if os.environ.get("FAIL_EXTRACT"): sys.exit(1)
    platform = "mac-arm64" if os.environ.get("FAKE_MACHINE") == "arm64" else "mac-x64"
    binary = pathlib.Path(args[-1]) / ("chrome-" + platform) / "Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
    binary.parent.mkdir(parents=True)
    binary.write_text("#!/bin/sh\nexit 0\n")
    binary.chmod(0o755)
elif tool != "open":
    sys.exit(1)
'''


class PortableBrowserTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        # macOS exposes /var through a symlink; registry entries must be canonical.
        self.base = Path(self.temporary.name).resolve()
        self.root = self.base / "source"
        (self.root / "scripts").mkdir(parents=True)
        shutil.copy(ROOT / "scripts/tailnet-browser.sh", self.root / "scripts")
        digest = hashlib.sha256(ARCHIVE).hexdigest()
        (self.root / "scripts/browser-version.sh").write_text(
            f"BROWSER_VERSION=155.0.8059.39\nBROWSER_MAC_X64_SHA256={digest}\nBROWSER_MAC_ARM64_SHA256={digest}\n"
        )
        shutil.copytree(ROOT / "chrome-extension", self.root / "chrome-extension")
        self.home = self.base / "home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for tool in ["uname", "curl", "shasum", "ditto", "open"]:
            path = self.bin / tool
            path.write_text(f"#!{sys.executable}\n" + FAKE_TOOL)
            path.chmod(0o755)
        self.log = self.base / "commands.jsonl"
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}", BROWSER_TEST_LOG=str(self.log))
        for name in ["CODYSSEY_BROWSER_CACHE_DIR", "CODYSSEY_BROWSER_SUPPORT_DIR"]:
            self.env.pop(name, None)
        self.cache = self.home / "Library/Caches/codyssey-init"
        self.support = self.home / "Library/Application Support/codyssey-init"

    def tearDown(self):
        self.temporary.cleanup()

    def run_launcher(self, *args, **environment):
        return subprocess.run(["bash", str(self.root / "scripts/tailnet-browser.sh"), *args],
            env=dict(self.env, **environment), text=True, capture_output=True, timeout=5)

    def calls(self, tool):
        if not self.log.exists(): return []
        return [call for line in self.log.read_text().splitlines() if (call := json.loads(line))[0] == tool]

    def test_x64_download_is_verified_and_reused(self):
        result = self.run_launcher("--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("/155.0.8059.39/mac-x64/chrome-mac-x64.zip", " ".join(self.calls("curl")[0]))
        self.assertEqual(len(self.calls("shasum")), 1)
        self.assertEqual(self.calls("open"), [])
        self.assertEqual(self.run_launcher("--prepare").returncode, 0)
        self.assertEqual(len(self.calls("curl")), 1)
        startup = self.support / "tailnet-chrome-extension/startup.json"
        self.assertEqual(json.loads(startup.read_text()), {"enableOnInstall": True})
        self.assertEqual(json.loads((self.root / "chrome-extension/startup.json").read_text()), {"enableOnInstall": False})

    def test_arm64_and_argument_preservation(self):
        url = "https://example.invalid/path?value=two words&literal=$(no-execution)"
        result = self.run_launcher(url, FAKE_MACHINE="arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("/mac-arm64/chrome-mac-arm64.zip", " ".join(self.calls("curl")[0]))
        call = self.calls("open")[0]
        self.assertEqual(call[-1], url)
        self.assertIn(f"--user-data-dir={self.support}/tailnet-chrome-profile", call)
        self.assertIn(f"--load-extension={self.support}/tailnet-chrome-extension", call)
        self.assertNotIn("/Applications", call[2])

    def test_registered_extensions_are_validated_deduplicated_and_ordered(self):
        first = self.base / "first extension"
        second = self.base / "second-extension"
        for path in [first, second]:
            path.mkdir()
            (path / "manifest.json").write_text("{}")
        stale = self.base / "stale-extension"
        missing_manifest = self.base / "missing-manifest"
        missing_manifest.mkdir()
        comma = self.base / "comma,extension"
        comma.mkdir()
        (comma / "manifest.json").write_text("{}")
        alias = self.base / "extension-alias"
        alias.symlink_to(first, target_is_directory=True)
        registry = self.support / "unpacked-extension-paths"
        registry.parent.mkdir(parents=True)
        registry.write_text(
            "\n".join([
                str(first), str(self.support / "tailnet-chrome-extension"),
                "relative-extension", str(stale), str(comma),
                str(alias), str(missing_manifest), str(first), str(second), "",
            ])
        )

        result = self.run_launcher("about:blank")

        self.assertEqual(result.returncode, 0, result.stderr)
        extension_flag = next(argument for argument in self.calls("open")[0] if argument.startswith("--load-extension="))
        built_in = self.support / "tailnet-chrome-extension"
        self.assertEqual(extension_flag, f"--load-extension={built_in},{first},{second}")
        for rejected in ["relative-extension", str(stale), str(comma), str(alias), str(missing_manifest),
            str(self.support / "tailnet-chrome-extension"), str(first)]:
            self.assertIn(rejected, result.stderr)

    def test_launcher_exposes_the_extension_registry_contract_marker(self):
        launcher = (self.root / "scripts/tailnet-browser.sh").read_text()

        self.assertIn("# codyssey-init: unpacked-extension-registry-v1", launcher.splitlines())

    def test_directory_registry_is_ignored_without_blocking_builtin_extension(self):
        registry = self.support / "unpacked-extension-paths"
        registry.mkdir(parents=True)

        result = self.run_launcher("about:blank")

        self.assertEqual(result.returncode, 0, result.stderr)
        built_in = self.support / "tailnet-chrome-extension"
        self.assertIn(f"--load-extension={built_in}", self.calls("open")[0])

    def test_fifo_registry_is_ignored_without_opening_it(self):
        registry = self.support / "unpacked-extension-paths"
        registry.parent.mkdir(parents=True)
        os.mkfifo(registry)

        result = self.run_launcher("about:blank")

        self.assertEqual(result.returncode, 0, result.stderr)
        built_in = self.support / "tailnet-chrome-extension"
        self.assertIn(f"--load-extension={built_in}", self.calls("open")[0])

    def test_failed_extension_canonicalization_is_ignored(self):
        extension = self.base / "canonicalization-failure"
        extension.mkdir()
        (extension / "manifest.json").write_text("{}")
        registry = self.support / "unpacked-extension-paths"
        registry.parent.mkdir(parents=True)
        registry.write_text(f"{extension}\n")
        bash_environment = self.base / "bash-environment"
        bash_environment.write_text(
            'cd() {\n'
            '  for argument in "$@"; do\n'
            '    [[ $argument != "$FAIL_CANONICAL_PATH" ]] || return 1\n'
            '  done\n'
            '  builtin cd "$@"\n'
            '}\n'
        )

        result = self.run_launcher(
            "about:blank", BASH_ENV=str(bash_environment), FAIL_CANONICAL_PATH=str(extension)
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        built_in = self.support / "tailnet-chrome-extension"
        self.assertIn(f"--load-extension={built_in}", self.calls("open")[0])
        self.assertIn(str(extension), result.stderr)

    def test_failures_leave_no_installed_browser_or_staging(self):
        for failure in ["FAIL_DOWNLOAD", "BAD_CHECKSUM", "FAIL_EXTRACT"]:
            with self.subTest(failure=failure):
                result = self.run_launcher("--prepare", **{failure: "1"})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(self.cache.iterdir()), [])
                self.assertEqual(self.calls("open"), [])

    def test_invalid_platform_and_flags_are_rejected_before_download(self):
        for args, environment in [((), {"FAKE_OS": "Linux"}), ((), {"FAKE_MACHINE": "unknown"}),
            (("--remote-debugging-port=9222",), {})]:
            with self.subTest(environment=environment, args=args):
                self.assertNotEqual(self.run_launcher(*args, **environment).returncode, 0)
        self.assertEqual(self.calls("curl"), [])

    def test_incomplete_existing_cache_is_preserved(self):
        directory = self.cache / "chrome-155.0.8059.39-mac-x64"
        directory.mkdir(parents=True)
        marker = directory / "keep.txt"
        marker.write_text("existing user data")
        self.assertNotEqual(self.run_launcher("--prepare").returncode, 0)
        self.assertEqual(marker.read_text(), "existing user data")
        self.assertEqual(self.calls("curl"), [])


if __name__ == "__main__":
    unittest.main()
