#!/usr/bin/env python3
"""Offline AppRun mount-contract regression; not a sandbox/runtime substitute."""

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
                "libmedia_kit_video_plugin.so", "libaudioplayers_linux_plugin.so",
                "libflutter_secure_storage_linux_plugin.so", "libwebview_all_linux_plugin.so")]
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

    def test_webkit_inner_sandbox_gets_a_real_readonly_helper_mount(self):
        with tempfile.TemporaryDirectory(prefix="fura launcher test ") as directory:
            root = Path(directory)
            appdir = root / "AppDir with spaces"
            helpers = appdir / "usr/lib/x86_64-linux-gnu/webkit2gtk-4.1"
            helpers.mkdir(parents=True)
            for name in ("WebKitWebProcess", "WebKitNetworkProcess"):
                helper = helpers / name
                helper.touch()
                helper.chmod(0o755)
            launcher = appdir / "AppRun"
            shutil.copyfile(APP_RUN_SOURCE, launcher)
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            bwrap = fake_bin / "bwrap"
            bwrap.write_text('''#!/usr/bin/env python3
import sys
from pathlib import Path
args = sys.argv[1:]
mounts = [(args[i+1], args[i+2]) for i, arg in enumerate(args) if arg == '--ro-bind']
target = '/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1'
assert any(args[i:i+2] == ['--tmpfs', '/usr/lib'] for i in range(len(args)-1)), 'REAL_MOUNT_SKELETON_REQUIRED'
assert not any(destination == '/usr/lib' for source, destination in mounts), 'NO_TEMPORARY_SYMLINK_VIEW'
assert any(destination == target and Path(source).name == 'webkit2gtk-4.1'
           for source, destination in mounts), 'HELPERS_MUST_BE_READONLY_BOUND'
helper_index = args.index(target)
remount_index = args.index('--remount-ro')
assert remount_index > helper_index and args[remount_index+1] == '/usr/lib', 'SKELETON_MUST_FINISH_READONLY'
print('APPIMAGE_HELPER_MOUNT_CONTRACT_PASS')
''')
            bwrap.chmod(0o755)
            result = subprocess.run(["bash", str(launcher)], capture_output=True, text=True,
                                    env=dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ["PATH"]),
                                    timeout=15, check=False)
            self.assertEqual(result.returncode, 0, "AppRun helper mount contract failed")
            self.assertIn("APPIMAGE_HELPER_MOUNT_CONTRACT_PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
