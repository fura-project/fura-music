"""Offline guard/privacy checks; no account input or service requests."""
import contextlib
import getpass
import io
import json
import sys
from types import SimpleNamespace
import unittest
import warnings
from unittest.mock import patch

import kugou_web_playback_gate as gate


class GateTests(unittest.TestCase):
    def test_default_and_noninteractive_entry_do_not_build_collect_or_request(self):
        for argv in [["gate"], ["gate", "--human-authorized-once"]]:
            with (patch.object(sys, "argv", argv),
                  patch.object(sys.stdin, "isatty", return_value=False),
                  patch.object(gate.subprocess, "run") as run,
                  patch.object(gate.getpass, "getpass") as secret,
                  contextlib.redirect_stdout(io.StringIO()) as output):
                self.assertIn(gate.main(), (0, 1))
            run.assert_not_called()
            secret.assert_not_called()
            self.assertIn("result=NOT_RUN", output.getvalue())

    def test_hidden_input_refuses_echoing_fallback(self):
        def fallback(_prompt):
            warnings.warn("terminal unavailable", getpass.GetPassWarning)
            self.fail("must not proceed to echoing input")
        with patch.object(gate.getpass, "getpass", fallback):
            with self.assertRaises(getpass.GetPassWarning):
                gate.hidden("synthetic prompt")

    def test_declined_budget_never_builds_or_reads_secrets(self):
        with (patch.object(sys, "argv", ["gate", "--human-authorized-once"]),
              patch.object(sys.stdin, "isatty", return_value=True),
              patch.object(sys.stderr, "isatty", return_value=True),
              patch("builtins.input", return_value="NO"),
              patch.object(gate.subprocess, "run") as run,
              patch.object(gate, "hidden") as secret,
              contextlib.redirect_stdout(io.StringIO()) as output):
            self.assertEqual(gate.main(), 0)
        run.assert_not_called()
        secret.assert_not_called()
        self.assertIn("CONSENT_NOT_GIVEN", output.getvalue())

    def test_consented_wrapper_uses_stdin_only_clears_buffer_and_filters_child_output(self):
        for child_output, expected in [
            (b"KUGOU_GATE result=PASS scope=STANDARD_SOURCE_ONLY production_enabled=false\n", 0),
            (b"Cookie=synthetic-private-secret\n", 1),
        ]:
            buffers = []

            def run(arguments, **options):
                self.assertNotIn("synthetic-private-secret", " ".join(arguments))
                self.assertNotIn("env", options)
                if arguments[:2] == ["cargo", "build"]:
                    self.assertNotIn("input", options)
                    return SimpleNamespace(returncode=0)
                if arguments[:2] == ["cargo", "metadata"]:
                    return SimpleNamespace(returncode=0, stdout=b'{"target_directory":"/synthetic-target"}')
                payload = options["input"]
                self.assertIsInstance(payload, bytearray)
                document = json.loads(payload)
                self.assertEqual(document["cookie_header"], "KugooID=42; t=synthetic-private-secret")
                self.assertTrue(document["probe_range"])
                self.assertEqual(arguments[-1], "--human-authorized-once")
                buffers.append(payload)
                return SimpleNamespace(returncode=0, stdout=child_output, stderr=b"synthetic-private-secret")

            with (patch.object(sys, "argv", ["gate", "--human-authorized-once", "--probe-range"]),
                  patch.object(sys.stdin, "isatty", return_value=True),
                  patch.object(sys.stderr, "isatty", return_value=True),
                  patch("builtins.input", side_effect=["AUTHORIZE ONE KUGOU WEB REQUEST", "YES"]),
                  patch.object(gate, "hidden", side_effect=["KugooID=42; t=synthetic-private-secret", "synthetic-capture", "synthetic-track", "synthetic-media.kugou.com"]),
                  patch.object(gate.subprocess, "run", side_effect=run) as process,
                  contextlib.redirect_stdout(io.StringIO()) as output):
                self.assertEqual(gate.main(), expected)
            self.assertEqual(process.call_count, 3)
            self.assertEqual(len(buffers), 1)
            self.assertFalse(any(buffers[0]))
            self.assertNotIn("synthetic-private-secret", output.getvalue())


if __name__ == "__main__":
    unittest.main()
