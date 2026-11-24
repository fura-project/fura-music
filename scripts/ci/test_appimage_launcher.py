#!/usr/bin/env python3
"""Offline tests of the AppRun environment and launch contract."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


APP_RUN_SOURCE = Path(__file__).resolve().parents[2] / "packaging/linux/assets/AppRun"


class AppImageLauncherTests(unittest.TestCase):
    def test_missing_mime_cache_is_rejected_before_elf_inspection(self):
        # File-shape fixture only; never claims ELF loading/window success.
        with tempfile.TemporaryDirectory() as directory:
            appdir = Path(directory) / "AppDir"
            bundle = appdir / "usr/lib/flutterustmusic"
            names = ["flutterustmusic", "data/icudtl.dat",
                     "data/flutter_assets/NativeAssetsManifest.json"]
            names += ["lib/" + name for name in (
                "libflutter_linux_gtk.so", "libapp.so", "librust_lib_flutterustmusic.so",
                "libmedia_kit_video_plugin.so", "libflutter_media_session_plugin.so",
                "libflutter_secure_storage_linux_plugin.so")]
            for name in names:
                path = bundle / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"shape-only-fixture")
            (appdir / "AppRun").touch()
            audit = APP_RUN_SOURCE.parent.parent / "audit_appimage.sh"
            result = subprocess.run(["bash", str(audit), str(appdir), str(Path(directory) / "report")],
                                    capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("AppImage MIME cache missing or empty", result.stderr)

    def test_portable_launcher_executes_directly_with_hooks_and_exact_arguments(self):
        with tempfile.TemporaryDirectory(prefix="fura launcher test ") as directory:
            root = Path(directory)
            appdir = root / "AppDir with spaces"
            (appdir / "apprun-hooks").mkdir(parents=True)
            (appdir / "apprun-hooks/gtk.sh").write_text("export FURA_TEST_HOOK=ran\n")
            launcher = appdir / "AppRun"
            shutil.copyfile(APP_RUN_SOURCE, launcher)
            executable = appdir / "usr/bin/flutterustmusic"
            executable.parent.mkdir(parents=True)
            executable.write_text('''#!/usr/bin/env bash
set -eu
test "$PWD" = "$APPDIR"
test "$FURA_APP_ROOT" = "$APPDIR/usr/lib/flutterustmusic"
test "$LD_LIBRARY_PATH" = "$FURA_APP_ROOT/lib:$APPDIR/usr/lib/x86_64-linux-gnu:$APPDIR/usr/lib"
test "$FURA_TEST_HOOK" = ran
test "$#" -eq 2
test "$1" = "first argument with spaces"
test "$2" = "--literal"
printf '%s\\n' "$$"
exit 42
''')
            executable.chmod(0o755)
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            bwrap = fake_bin / "bwrap"
            bwrap.write_text("#!/bin/sh\nexit 99\n")
            bwrap.chmod(0o755)
            env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]}
            env.pop("LD_LIBRARY_PATH", None)
            with subprocess.Popen(
                ["bash", str(launcher), "first argument with spaces", "--literal"],
                cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ) as process:
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 42, stderr)
                self.assertEqual(stdout.strip(), str(process.pid))


if __name__ == "__main__":
    unittest.main()
