"""Verify browser control retries and owned-resource cleanup without a browser."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class BrowserConfigurationRetryTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location("browser_config", ROOT / "scripts/configure-tailnet-browser.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_cleaned_up_socket_timeout_retries_once_then_succeeds(self):
        module = self.module()
        failure = RuntimeError("enabling Chrome Developer mode: timed out")
        failure.__cause__ = TimeoutError("timed out")
        output = io.StringIO()
        with patch.object(module, "configure", side_effect=[failure, None]) as configure, contextlib.redirect_stderr(output):
            module.configure_with_retry("binary", "profile", "extension", "extensions")
        self.assertEqual(configure.call_count, 2)
        self.assertIn("retrying once", output.getvalue())

    def test_repeated_timeout_remains_a_failure_and_stops_after_two_attempts(self):
        module = self.module()
        with patch.object(module, "configure", side_effect=TimeoutError("timed out")) as configure, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(TimeoutError):
                module.configure_with_retry("binary", "profile", "extension", "extensions")
        self.assertEqual(configure.call_count, 2)

    def test_policy_and_incomplete_shutdown_errors_are_never_retried(self):
        module = self.module()
        for message in ("another extension or policy controls the proxy", "Chrome setup is still closing"):
            with self.subTest(message=message), patch.object(module, "configure", side_effect=RuntimeError(message)) as configure:
                with self.assertRaisesRegex(RuntimeError, message):
                    module.configure_with_retry("binary", "profile", "extension", "extensions")
                self.assertEqual(configure.call_count, 1)

    def test_target_cleanup_failure_is_not_retried_even_when_caused_by_timeout(self):
        module = self.module()
        failure = module.BrowserCleanupError("setup tabs did not close")
        failure.__cause__ = TimeoutError("timed out")
        with patch.object(module, "configure", side_effect=failure) as configure:
            with self.assertRaises(module.BrowserCleanupError):
                module.configure_with_retry("binary", "profile", "extension", "extensions")
        self.assertEqual(configure.call_count, 1)

    def test_failed_attempt_closes_only_owned_tabs_before_browser_retry(self):
        module = self.module()
        events, closed, launches = [], [], []
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory)
            class Browser:
                def __init__(self, *args, **kwargs):
                    self.number = len(launches)+1
                    launches.append(self)
                    self.returncode = None
                    (profile/'DevToolsActivePort').write_text('9222\n')
                    events.append(f'start:{self.number}')
                def poll(self):
                    return self.returncode
                def terminate(self):
                    self.returncode = 0
                    events.append(f'terminate:{self.number}')
                def wait(self, **kwargs):
                    events.append(f'wait:{self.number}')
                    return 0
            class Response:
                def __init__(self, data):
                    self.data = data
                def __enter__(self):
                    return self
                def __exit__(self, *args):
                    pass
                def read(self):
                    return json.dumps(self.data)
            def request(value, **kwargs):
                url = value.full_url if hasattr(value, 'full_url') else value
                if '/json/new?' in url:
                    name = 'manager' if 'chrome%3A' in url else 'popup'
                    identifier = f'{name}-{len(launches)}'
                    return Response({'id': identifier, 'webSocketDebuggerUrl': 'ws://127.0.0.1/'+identifier})
                identifier = url.rsplit('/', 1)[-1]
                closed.append(identifier)
                events.append('close:'+identifier)
                return Response({})
            class Client:
                def __init__(self, url):
                    self.socket = type('Socket', (), {'close': lambda self: None})()
                def evaluate(self, expression):
                    if len(launches) == 1:
                        raise TimeoutError('timed out')
                    if 'typeof chrome' in expression:
                        return True
                    if 'getExtensionsInfo' in expression:
                        return {'name': 'Codyssey Tailnet', 'state': 'ENABLED'}
                    if 'sendMessage' in expression:
                        return {'status': {'blocked': False}}
                    return {}
            with patch.object(module.subprocess, 'Popen', Browser), patch.object(module, 'CDP', Client), \
                 patch.object(module.urllib.request, 'urlopen', request), contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()):
                module.configure_with_retry(Path('/browser'), profile, Path('/extension'), '/extension')
            self.assertEqual(closed, ['manager-1', 'popup-2', 'manager-2'])
            self.assertLess(events.index('close:manager-1'), events.index('terminate:1'))
            self.assertLess(events.index('wait:1'), events.index('start:2'))
            self.assertFalse((profile/'DevToolsActivePort').exists())


if __name__ == "__main__":
    unittest.main()
