#!/usr/bin/env python3
"""Offline failure classification; real preflight remains required in CI."""

import contextlib
import io
import os
import subprocess
import unittest
from unittest.mock import patch

import probe_appimage_sandbox as probe


class SandboxProbeTests(unittest.TestCase):
    def invoke(self, result):
        with (patch.object(probe.os, "geteuid", return_value=1000),
              patch.object(probe, "diagnostics"),
              patch.dict(os.environ, {}, clear=True),
              patch.object(probe.subprocess, "run", return_value=result) as run,
              contextlib.redirect_stdout(io.StringIO()) as output):
            code = probe.main()
        return code, output.getvalue(), run

    def test_uid_gid_and_other_errors_are_environment_failures_not_app_failures(self):
        for stderr, category in ((b"bwrap: setting up uid map: Permission denied", "UID_MAP_DENIED"),
                                 (b"bwrap: setting up gid map: Permission denied", "GID_MAP_DENIED"),
                                 (b"private-profile-or-path", "NAMESPACE_UNAVAILABLE")):
            code, output, run = self.invoke(subprocess.CompletedProcess([], 1, b"private", stderr))
            self.assertEqual(code, 78)
            self.assertIn("ENVIRONMENT_BLOCKED", output)
            self.assertIn(category, output)
            self.assertNotIn("private", output)
            self.assertEqual(run.call_args.kwargs["timeout"], 15)

    def test_success_does_not_claim_appimage_startup(self):
        code, output, run = self.invoke(subprocess.CompletedProcess([], 0, b"", b""))
        self.assertEqual(code, 0)
        self.assertIn("APPIMAGE_LAUNCH_NOT_YET_TESTED", output)
        command = run.call_args.args[0]
        self.assertIn("--unshare-user", command)
        self.assertIn("--unshare-pid", command)
        self.assertNotIn("--no-sandbox", command)

    def test_timeout_and_missing_tool_fail_closed_without_exception_values(self):
        for error in (subprocess.TimeoutExpired("private-command", 15), OSError("private-path")):
            with (patch.object(probe.os, "geteuid", return_value=1000),
                  patch.object(probe, "diagnostics"),
                  patch.dict(os.environ, {}, clear=True),
                  patch.object(probe.subprocess, "run", side_effect=error),
                  contextlib.redirect_stdout(io.StringIO()) as output):
                self.assertEqual(probe.main(), 78)
            self.assertNotIn("private", output.getvalue())

    def test_root_or_sandbox_bypass_is_never_accepted(self):
        for uid, environment in ((0, {}), (1000, {"WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS": "1"})):
            with (patch.object(probe.os, "geteuid", return_value=uid),
                  patch.dict(os.environ, environment, clear=True),
                  patch.object(probe.subprocess, "run") as run,
                  contextlib.redirect_stdout(io.StringIO())):
                self.assertEqual(probe.main(), 1)
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
