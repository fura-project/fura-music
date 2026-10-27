"""Offline rejection/privacy checks for the retired standalone wrapper."""

import ast
import contextlib
import io
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


EXPECTED = "KUGOU_GATE result=NOT_RUN reason=RUST_CALLER_REQUIRED\n"
PRIVATE = "synthetic-private-sentinel"
INVOCATIONS = (
    (),
    ("--human-authorized-once",),
    ("--probe-range",),
    ("--human-authorized-once", "--probe-range"),
    ("--probe-range", "--human-authorized-once"),
    ("--human-authorized-once", "--human-authorized-once", "--probe-range"),
    ("--human-authorized-once=false", "--probe-range=true"),
    ("--help",),
    ("-h",),
    ("--unknown", PRIVATE),
    ("--cookie", "KugooID=42; t=" + PRIVATE),
    ("--signed-url", "https://synthetic.invalid/songinfo?token=" + PRIVATE),
    ("--token=" + PRIVATE,),
    ("--track-opaque", PRIVATE),
    ("--approved-media-host", "synthetic.invalid"),
    ("--track-id", PRIVATE),
    ("--current-track-id-file", "/synthetic/" + PRIVATE),
    ("--export-current-track-id",),
    ("--lookup", PRIVATE),
    ("--human-authorized-once", "--probe-range", PRIVATE),
    ("--", "https://synthetic.invalid/media?token=" + PRIVATE),
)


class GateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        script = Path(__file__).with_name("kugou_web_playback_gate.py")
        cls.source = script.read_text(encoding="utf-8")
        cls.code = compile(cls.source, str(script), "exec")

    def setUp(self):
        self.output = self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        self.error = self.enterContext(contextlib.redirect_stderr(io.StringIO()))
        # Compile before installing guards so even import-time behavior is checked.
        self.guards = [
            self.enterContext(patch(target, side_effect=AssertionError(target)))
            for target in (
                "builtins.input",
                "builtins.open",
                "io.open",
                "os.open",
                "os.getenv",
                "getpass.getpass",
                "subprocess.run",
                "subprocess.Popen",
                "os.system",
                "os.popen",
                "socket.socket",
                "socket.create_connection",
                "socket.getaddrinfo",
                "urllib.request.urlopen",
                "webbrowser.open",
                "webbrowser.open_new",
                "webbrowser.open_new_tab",
                "webbrowser.get",
            )
        ]
        self.stdin = self.enterContext(patch.object(sys, "stdin"))
        self.enterContext(patch.object(sys, "__stdin__", self.stdin))
        for method in ("read", "readline", "readlines"):
            getattr(self.stdin, method).side_effect = AssertionError("stdin read")
        self.enterContext(patch.dict(os.environ, {
            "KUGOU_COOKIE": PRIVATE,
            "KUGOU_TOKEN": PRIVATE,
            "KUGOU_SIGNED_URL": "https://synthetic.invalid/?token=" + PRIVATE,
            "KUGOU_TRACK_OPAQUE": PRIVATE,
            "FURA_CURRENT_TRACK_ID_FILE": "/synthetic/" + PRIVATE,
        }))

    def tearDown(self):
        for guard in self.guards:
            guard.assert_not_called()
        self.assertEqual(self.stdin.mock_calls, [])
        self.assertEqual(self.error.getvalue(), "")

    def test_source_has_no_secret_input_or_external_execution_path(self):
        tree = ast.parse(self.source)
        self.assertFalse(any(
            isinstance(node, (ast.Import, ast.ImportFrom))
            for node in ast.walk(tree)
        ))
        calls = [node.func for node in ast.walk(tree) if isinstance(node, ast.Call)]
        self.assertTrue(all(isinstance(call, ast.Name) for call in calls))
        self.assertEqual({call.id for call in calls}, {"print", "main", "SystemExit"})

    def test_import_does_not_run_or_accept_input(self):
        namespace = {"__name__": "kugou_web_playback_gate"}
        exec(self.code, namespace)
        self.assertNotIn("hidden", namespace)
        self.assertEqual(self.output.getvalue(), "")

    def test_every_invocation_is_fixed_not_run_without_side_effects(self):
        for entry in ("main", "script"):
            for tty in (False, True):
                for args in INVOCATIONS:
                    with self.subTest(entry=entry, tty=tty, args=args):
                        self.output.seek(0)
                        self.output.truncate(0)
                        self.stdin.isatty.return_value = tty
                        with (patch.object(sys, "argv", ["gate", *args]),
                              patch.object(self.error, "isatty", return_value=tty)):
                            namespace = {"__name__": (
                                "__main__" if entry == "script"
                                else "kugou_web_playback_gate"
                            )}
                            if entry == "script":
                                with self.assertRaises(SystemExit) as stopped:
                                    exec(self.code, namespace)
                                self.assertEqual(stopped.exception.code, 0)
                            else:
                                exec(self.code, namespace)
                                self.assertEqual(namespace["main"](), 0)
                        self.assertEqual(self.output.getvalue(), EXPECTED)


if __name__ == "__main__":
    unittest.main()
