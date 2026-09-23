# Cross-platform development test packages

The `Cross-platform development packages` GitHub Actions workflow builds short-lived artifacts for maintainer-operated runtime testing. It is manual-only: open **Actions**, select the workflow, choose the branch or commit, and select **Run workflow**. Artifacts are attached to that workflow run for seven days.

These artifacts are not releases. They retain the current generated application identity and have not completed production signing, notarization, store packaging, or the native-video distribution-notice review tracked by HD-001, TD-002, and TD-006. Do not redistribute or publish them.

## Artifacts and truthful test boundary

| Artifact | Intended use | Important boundary |
| --- | --- | --- |
| `flutterustmusic-android-arm64-development.apk` | Physical ARM64 Android phone or tablet | Built in Release mode but signed with the repository's development/debug key. It is not a production APK. |
| `flutterustmusic-android-x64-debug.apk` | x64 Android Emulator | Debug-only emulator package; it does not prove ARM64 physical-device behavior. |
| `flutterustmusic-*-ubuntu24.04-amd64.deb` | Ubuntu 24.04 x86_64 | Native package containing the complete private Flutter bundle. APT resolves its Ubuntu runtime dependencies; it is not claimed to support every Debian release. |
| `flutterustmusic-*.fc43-x86_64.rpm` | Fedora 43 x86_64 | Native RPM with automatic ELF requirements plus the media/plugin runtime requirements that are loaded outside ordinary ELF linkage. It is not a generic package for every RPM distribution. |
| `flutterustmusic-*-arch-x86_64.pkg.tar.zst` | Current Arch Linux x86_64 | Real pacman package built by non-root `makepkg` in the recorded rolling Arch environment. Rolling-repository ABI drift is outside the seven-day artifact window. |
| `flutterustmusic-*-ubuntu24.04-x86_64.AppImage` | Portable x86_64 Linux test on Ubuntu 24.04 and Fedora 43 | Carries the application bundle and non-base GTK/media/WebKit libraries. It still relies on the kernel, glibc, graphics stack, fonts/fontconfig, CA certificates, a D-Bus desktop session, and WebKit sandbox helpers supplied by the target system. |
| `flutterustmusic-windows-x64-development.zip` | x64 Windows 10 or 11 | Extract the whole directory before launching `flutterustmusic.exe`; individual DLLs must remain beside the executable. It is not MSIX-signed or Store-packaged. |
| `flutterustmusic-macos-development.zip` | macOS architecture(s) listed in `MACOS_ARCHITECTURES.txt` | The `.app` is neither Developer ID signed nor notarized. It is a compile/test artifact, not a distributable macOS release. |
| `flutterustmusic-ios-simulator-development.zip` | Xcode iOS Simulator architecture(s) listed in `IOS_SIMULATOR_ARCHITECTURES.txt` | Debug-mode Simulator package. Flutter does not support mobile Release mode on a simulator. It cannot be installed on a physical iPhone or iPad and does not prove physical-device background audio, lock-screen controls, or Keychain behavior. |

There is no Web artifact because the product's Rust core, secure-storage, native audio/video, and operating-system media integrations are native-target capabilities; Web is not a supported product target.

## What CI proves

Before packaging begins, one Ubuntu job runs the locked Rust workspace format, test, and strict Clippy gates plus Dart formatting, `dart analyze`, and all Flutter tests. Platform jobs then prove that the named source revision compiles into the named package. The no-define test request is D: MediaKit plus Flutter Media Session. Android, Windows and macOS resolve that request directly; Linux deliberately resolves it to MediaKit plus Fura MPRIS; iOS deliberately resolves it to MediaKit plus AudioService. These effective-platform rules do not imply native runtime acceptance.

The Android job additionally verifies the default-D selector regression, Internet permission, both retained media-service declarations, the ARM64 MediaKit payload, the Rust bridge, the Android rustls certificate-verifier class, and the process-startup JNI initializer. The artifact includes `PLAYBACK_STACK.txt` with the requested/effective Android stack and exact source commit. That file identifies the build; only the runtime `FURA_DIAGNOSTIC playback_stack` event and physical system inspection can prove which edge initialized and whether a duplicate session or notification exists.

The Linux path is a set of independently failing jobs inside the single `Cross-platform development packages` workflow. It builds separate Release bundles on Ubuntu 24.04, Fedora 43, and Arch rather than relabeling one Ubuntu binary for every package manager. It checks every ELF in each bundle, rejects unresolved libraries and build-machine RPATHs, and records the maximum referenced GLIBC/GLIBCXX symbol versions. Plugin `DT_NEEDED` entries are inspected without requiring a shared object to have an executable bit, and the target runtime linker must also resolve each required SONAME. The AppImage audit applies the same rule to every extracted ELF: each dependency is reported as bundled, supplied by the controlled target base, or missing; it does not execute 0644 shared objects through `ldd`. Ubuntu also runs the existing offline MPRIS/media initialization, local H.264 media, and WebKitGTK lifecycle integrations under temporary D-Bus/X11 sessions.

Some Linux build hosts have a JDK installed and cause the transitive `package:jni` build hook to emit `libdartjni.so` even though Fura declares no Linux JNI native asset. Packaging removes that optional host-JVM helper only when both generated native-asset manifests are empty and no bundled ELF has a `DT_NEEDED` edge to it. The clean installed-package startup is the runtime guard that Fura does not depend on the omitted helper; the Android JNI payload and Android package are unaffected.

Each native package is queried with its package manager, installed with dependency resolution in a clean target container, launched as an ordinary user from an unrelated path containing spaces, reinstalled, and removed. The startup gate waits for an actual X11 window; a process merely surviving until a timeout is not success. The uninstall check confirms that a synthetic user configuration sentinel remains untouched. The AppImage is extracted and audited, then its packaged `AppRun` is started in clean Ubuntu 24.04 and Fedora 43 containers that do not preinstall GTK, GStreamer, libmpv, WebKitGTK, or libsecret. CI extraction proves the supported no-FUSE path only; it does not claim that a real FUSE mount was exercised.

A green workflow does not prove real-account QQ Music behavior, physical Android or Apple behavior, Windows SMTC usability, Linux desktop-shell integration, codecs on another machine, signing, notarization, store acceptance, or release readiness. Those observations remain per-target maintainer tests.

The consolidated Linux artifact is uploaded only after all four non-empty formats pass their format-specific validation. It contains `SHA256SUMS`, this boundary note, and source-run metadata. Every Linux package also carries `BUILD-INFO.txt`, the project license, Flutter/Dart notices, and the available resolved Rust dependency license texts. The AppImage additionally carries Debian copyright records for the host libraries selected into the image. This supports review of the development artifacts but does not close the formal native-media redistribution review tracked by TD-006.

## Linux installation and removal

Use only the package intended for the named target baseline. Native package managers resolve declared runtime dependencies; do not install with dependency checks disabled.

### Ubuntu 24.04 DEB

```bash
sudo apt install ./flutterustmusic-*-ubuntu24.04-amd64.deb
flutterustmusic
sudo apt remove flutterustmusic
```

The payload is installed under `/usr/lib/flutterustmusic`; `/usr/bin/flutterustmusic` is a short launcher that preserves the bundle-relative `lib/` and `data/` layout. Secret persistence requires a Secret Service provider from the desktop session, such as GNOME Keyring; the package does not start a second credential service.

### Fedora 43 RPM

```bash
sudo dnf install ./flutterustmusic-*.fc43-x86_64.rpm
flutterustmusic
sudo dnf remove flutterustmusic
```

Fedora 43 supplies `mpv-libs`, including the required `libmpv.so.2`, in the Fedora repositories used by the package job. The spec retains RPM's ELF dependency generator and supplements it with GStreamer plugin sets, certificate/font resources, and other runtime-loaded components.

### Arch Linux package

```bash
sudo pacman -U ./flutterustmusic-*-arch-x86_64.pkg.tar.zst
flutterustmusic
sudo pacman -R flutterustmusic
```

The uploaded artifact includes the concrete PKGBUILD used by CI. Its `depends` names are Arch packages, not copied Ubuntu or Fedora package names.

### AppImage

On the declared Ubuntu 24.04 or newer x86_64 baseline:

```bash
chmod +x flutterustmusic-*-ubuntu24.04-x86_64.AppImage
./flutterustmusic-*-ubuntu24.04-x86_64.AppImage
```

The image deliberately does not bundle glibc, the ELF dynamic loader, the Linux kernel, GPU drivers, fonts/fontconfig, CA certificates, the D-Bus session, `bubblewrap`, or `xdg-dbus-proxy`. Those remain base-system capabilities; `bubblewrap` must be able to create an unprivileged mount namespace. The image does carry the complete Flutter/Rust application bundle, GTK support gathered by the pinned linuxdeploy GTK plugin, the direct HarfBuzz runtime edge required by bundled PangoFT2, libmpv and its selected transitive libraries, GStreamer base/good modules and scanner, libsecret's client library, WebKitGTK, and its auxiliary processes. It does not disable WebKit sandboxing.

The Ubuntu WebKitGTK library resolves auxiliary processes through its compiled multiarch path. `AppRun` therefore uses the target's `bubblewrap` to construct a private, read-only `/usr/lib` view that preserves the target libraries while mapping only the packaged WebKit helper directory at that expected path. It executes linuxdeploy's GTK hooks before launch and leaves WebKit's own child-process sandbox enabled. Failure to create that namespace or find both WebKit process helpers is a startup failure, not a signal to fall back to a host WebKit installation.

When FUSE is unavailable, use AppImage's supported extraction path:

```bash
./flutterustmusic-*-ubuntu24.04-x86_64.AppImage --appimage-extract
./squashfs-root/AppRun
```

Running the extracted tree verifies the no-FUSE execution path. It is not evidence that FUSE mounting works on that machine.

## Linux verification limits

A green Linux aggregate proves that the four package files were generated from one source commit and app version, their metadata/file lists were queried, declared dependencies resolved in the named clean environments, and the installed or extracted application created a real window with the Flutter engine and Rust bridge loadable. The offline source integrations cover Linux MPRIS ownership, media-kit initialization and local H.264 playback, plus WebKitGTK cookie/data and lifecycle behavior. ELF and payload audits cover the directly linked plugins, GStreamer module/scanner presence, WebKitGTK helper processes, and removal of runner/source paths from delivered RPATHs.

It does not prove every codec, hardware acceleration path, Secret Service implementation, desktop shell, display server, older glibc, other Debian/RPM distribution, real-account login, live media source, FUSE setup, package signing, repository policy, or formal external redistribution approval. Those remain explicit Human/device/distribution follow-ups rather than being inferred from a green container run.

## Android anonymous HTTPS runtime check

After installing a newly built APK on an Android target, the bounded public QQ Music HTTPS regression can be run explicitly with:

```bash
flutter test integration_test/android_anonymous_https_test.dart \
  -d <android-device-id> \
  --dart-define=QQMUSIC_LIVE_TESTS=true
```

This check performs one anonymous, size-one public Track search. It does not read stored credentials, mutate an account, or print/persist returned Track content. APK inspection proves only that the required verifier components are packaged and wired; successful execution on an Android target is still required to prove platform TLS and current QQ reachability.
