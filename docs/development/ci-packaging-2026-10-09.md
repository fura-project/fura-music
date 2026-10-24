# Development-package failure investigation — 2026-10-09

Execution: `HUMAN_DIRECTED`; domain: CI / Packaging / Artifact Security;
acceptance: `HUMAN_REVIEW`. No commit or push is authorized. Product UI, Queue,
playback selection, providers, authentication and settings schema are unchanged.

## Baseline and original failure evidence

Clean initial HEAD, tracked origin/main and live GitHub main:
`0d555f8e09dafdd5c7eb0c6d8cc98d6615735b10`.
[Failed run 37769693045](https://github.com/fura-project/fura-music/actions/runs/37769693045)
used `7fd3329ab359267d9e90a0a83384a4e8fe6b9624`. These revisions had identical
relevant packaging/workflow implementations before this candidate. The failed
revision was not checked out or used to replace current product code.

All four job logs were downloaded and read, not just the error summaries:

| Job | Actual failing stage | Evidence and limits |
| --- | --- | --- |
| Linux AppImage, job 113288560732 | Runtime download digest verification | `continuous` asset changed while the expected digest remained fixed; no AppImage was produced. |
| Android ARM64, job 113288560772 | Final APK privacy audit, after successful Release build | Container and nested `lib/arm64-v8a/libmpv.so` HOME hits. Independently downloaded upstream payload and fresh local APK reproduce the same bytes; this is not a Rust bridge or Internet-permission compile failure. |
| macOS, job 113288560821 | Final .app privacy audit, after successful Release build | Workspace hits in Runner, Rust and source-built MediaKit plugin frameworks; HOME hits in prebuilt mpv/FFmpeg and support frameworks. Original failed .app was not uploaded, so the precise first-party section is **NOT VERIFIED**, rather than inferred from flags alone. |
| Windows, job 113288560825 | Final Release bundle privacy audit | Workspace hits in audioplayers/webview plugin DLLs, HOME in Rust DLL; slash variants duplicated reports. Original failed DLLs were not uploaded: exact PE section/RSDS attribution is **NOT VERIFIED**. |

Offline quality, DEB/RPM/Arch and iOS Simulator success in the old run remain
historical evidence; they are not fresh candidate passes. Raw logs and temporary
artifacts are outside Git in `/tmp/fura-packaging-audit-mO3qAt/`. Matched private
bytes are neither printed in diagnostics nor copied into this document.

## AppImage pin and supply-chain boundary

[type2-runtime release 20251108](https://github.com/AppImage/type2-runtime/releases/tag/20251108)
exists at upstream commit `dd6cebedcbddde9c82f89b011e8e1d40b6e43868`.
`runtime-x86_64` is 944632 bytes; both the API asset digest and the independent
download give SHA256
`2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d`.
The release API does **not** mark it immutable. The date-tag URL plus strict
expected hash pins content and rejects an upstream replacement; it does not
claim GitHub enforces immutability. TOOLS.txt now records tag, URL and hash.
linuxdeploy, appimagetool and GTK plugin pins remain unchanged.

Offline tests exercise the production curl/hash helper with valid content,
wrong hash, truncated download and failed transport. No automatic digest
refresh, fallback mirror, warning-only audit or `continue-on-error` is added.

## Path origin and precise upstream classification

`upstream_media_privacy.json` records three public upstream archives and exact
payload/string fingerprints. `verify_upstream_media_privacy.py` independently
checks downloaded archive hashes, binary origin, sections and complete NUL
string hashes without downloading or automatically rewriting policy.

- Android media_kit_libs_android_video 1.3.8 consumes libmpv build v1.1.7.
  ARM64 and x64 archive digests are respectively
  `4363dfa5d3d415b91c1f16f6fb90c3fe59a77dfd3f9b824d2b24b492d6b09df9`
  and `90268cd15f0766e07fb8e427388c621161177c9eb343c544f327bd63232bb236`.
  ARM64 libmpv has no DWARF/debug sections; its four public runner-root
  occurrences belong to three `.rodata` build-config strings. Final APK libmpv
  and the upstream JAR binary are byte-identical. Stripping cannot remove this
  runtime rodata safely; the payload is preserved, not patched or deleted.
- macOS media_kit_libs_macos_video 1.1.4 consumes libmpv-darwin v0.6.0, archive
  SHA256 `84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6`.
  Upstream Mpv and support libraries contain STABS/N_OSO symbol-string build
  paths; these remain rejected until native debug stripping removes them.
  Eight frameworks also contain public upstream config roots in
  `__TEXT,__cstring`: Mpv, Xml2 and six FFmpeg libraries. They receive only
  exact occurrence classification, after all loadable sections and runtime
  linkedit fingerprints match the independently downloaded upstream binary.

No first-party Runner, Rust or source-built plugin receives an exception.
Unproven names, other runner paths, appended content and changed binary/string
hashes are rejected. Personal marker/old application ID are never classified,
even inside proven upstream bytes. A whole HOME, section or binary is not
exempted. ZIP recursion audits payloads, entry metadata, comments and trailing
data; proven identical stored member bytes are delegated to their recursive
audit, avoiding the Android container duplicate without omitting its content.

Diagnostics report redacted file identity, category, format, section, offset,
stage and provenance, not matched bytes. Invalid ZIP/parse/read errors fail
closed with a category-only diagnostic. Windows checks are case-insensitive,
support uniform or mixed separators, non-ASCII case variants and UTF-8/UTF-16
encodings.

## Windows build-time candidate — native acceptance still open

Both named plugin CMake builds use Microsoft WIL. The pinned WIL headers
document Release `RESULT_DIAGNOSTICS_LEVEL=3` embedding `__FILE__`, while level
2 retains line numbers, return addresses and error handling without source
filenames. The private packaging build sets level 2 only on those two targets,
not a blanket DLL audit exemption. Ordinary IDE builds remain unchanged.

Rust `--remap-path-prefix` still handles source provenance. The encoded flag
list now preserves repeated `-C` tokens instead of deduplicating individual
tokens. Cargokit's implementation inherits this environment. Rust remapping
does not control linker CodeView/RSDS PDB references; the private build also
uses Microsoft's documented
[`/PDBALTPATH:%_PDB%`](https://learn.microsoft.com/en-us/cpp/build/reference/pdbaltpath-use-alternate-pdb-path?view=msvc-170)
for Rust and CMake linkers.
No DLL bytes, exports, plugin registration or FRB code are rewritten. Do not
claim the original Rust HOME hit is proven to be RSDS until a native artifact
can be inspected. C++ `/pathmap` is deliberately not used: the unrelated
C#/VB option is not an evidenced MSVC C++ switch.

CompanyName, LegalCopyright and ProductName are enforced. Bundle and final ZIP
both retain strict audits. Fresh MSVC build, exports/FRB loading, metadata and
Windows startup are **NOT VERIFIED** on this Linux host.

## macOS build-time candidate — native acceptance still open

The privacy wrapper uses Flutter's supported `FLUTTER_XCODE_*` override path
for copy/deployment debug stripping and quoted Clang file/debug prefix maps.
Caller C flags and existing runtime defines are preserved. No signing profile,
production identity or provider/engine changes are made.

After embedding, `strip_macos_debug.py` requires native Xcode, an existing .app
and ad-hoc signatures on every affected binary/bundle **before any mutation**.
Only files proven to contain DWARF/STABS are stripped with `xcrun strip -S`.
Before/after checks retain loadable section bytes, external/undefined symbols,
N_INDR targets, dyld bind/rebase/export/fixup data, exported names, architectures
and install names. Any change is fatal. Only affected seals are repaired
inner-to-outer, preserving metadata; final `codesign --verify --deep --strict`
precedes strict final .app/ZIP audits. Symlinks escaping the .app are refused.

Negative evidence: Linux LLVM `strip -S` corrupted indirect-export target
indexes in Avcodec, Avfilter and Avformat despite unchanged loadable sections
and exported-name-only `nm` output. That proxy result is **not** acceptance.
The additional linkedit regression/guard catches it. No LLVM-strip proxy is
used in production. Native Apple strip/codesign and final .app startup remain
**NOT VERIFIED**; failure of those guards must not be bypassed.

## Validation and retained negative trials

The local Linux/Android branch is verified; native Windows/macOS acceptance and
a fresh complete hosted run remain open. Packaging-code snapshot identifier
(SHA256 of the ordered eleven code/config file SHA256 lines, excluding docs):
`e09e4a36709b3d7a5ed6f7ff9ec67c5f85378933ede4ce1cc8476a07a792ed54`.
The files are workflow, Windows CMake, fetch/test AppImage tools, artifact audit,
privacy build wrapper, native sections, macOS debug preparation, privacy tests,
upstream manifest and its evidence verifier. This is an uncommitted candidate,
not a new Git source revision or hosted-run result.

- All 21 privacy unit tests pass, covering first-party/private path rejection, personal ID,
  Windows encodings, strict upstream provenance, ZIP/metadata, sanitized errors,
  Rust flags, macOS real-signature rejection, strip contract and signing order,
  indirect exports and dyld binding changes. These mock/native-format tests do
  not prove native MSVC/Xcode behavior.
- Fresh ARM64/x64 Release APKs, both strict final audits and both full manifest,
  native MediaKit/helper/Rust, verifier DEX/JNI inspections pass. Default stack
  selector tests pass without an engine override. No connected Android device
  is available; physical install, network/audio and system-media behavior are
  **NOT VERIFIED**, not inferred from ELF/DEX inspection.
  Candidate APK digests (both outside Git): ARM64
  `18af40e6c2fbbec247155d5a7b72ead20fee2493e3091edc8bd4d3e83f062351`;
  x64 `91f213c6be423b8ea7ac97bac39eca567e78960d4b43fda887c98ad56c5d444e`.
- Linux validation uses disposable Ubuntu 24.04/Fedora 43 OCI filesystems via
  unprivileged user/mount namespaces, not host package installation. The Ubuntu
  builder has Flutter 3.47.1 and official Rust 1.97.1; clean targets install only
  the workflow's declared graphics/audio/font/CA/D-Bus/sandbox base and Xvfb
  harness, not GTK/GStreamer/mpv/WebKit/libsecret application runtime packages.
  OCI digests: Ubuntu
  `sha256:f610ab94648195aa356059f5b41d6085c9d4d903c072430cdd1af7bdb646106b`;
  Fedora `sha256:1ad64e0ebefee83263fffacc5cb139b37ff70def215e4fe44720896c83353132`.
- Fresh Ubuntu Release build, strict bundle audit, pinned tool fetch, full
  AppImage construction, SHA256 check, extraction, final AppDir privacy audit
  and ordinary-user **actual X11 window** startup pass in both clean targets.
  Runtime packages were verified absent before each launch. Both were repeated
  after correcting an inherited `XDG_RUNTIME_DIR` to an owned 0700 directory;
  the first D-Bus directory warning is retained separately, not erased by the
  later clean runs. These are OCI filesystem/user-namespace tests on the host
  kernel, not new GitHub jobs or FUSE mount acceptance. Final audit sees 438
  ELF files, maximum GLIBC 2.39 and GLIBCXX 3.4.32. AppImage SHA256:
  `a982f0fbfa3d51caf06482b5345d00a9a58e22c91b32a7653f9833ef541a7286`.
- AppImage transport/digest/pin tests, packaging helpers, non-executable ELF
  dependency tests, Android bounded-retry tests, DEB discovery/install tests,
  all eight default playback-stack selector tests, source privacy/application
  identity audits, scoped ShellCheck/Bash syntax, actionlint 1.7.12 (all 14
  workflow jobs), 65 embedded Bash blocks and whitespace checks pass. No Rust
  domain/Bridge/Dart production code changed; native builds compile the real
  Rust/Flutter payload, not synthetic replacement libraries. A new full hosted
  quality gate is not claimed from this set of local tests.
- Retained harness failures: incomplete UID map blocked apt's `_apt` user;
  isolated PATH/tmp permissions blocked dpkg/apt; missing hashed pub-cache
  records blocked config-only; missing desktop-file-utils blocked packaging.
  All were fixed inside the disposable environment, not by weakening jobs.
  Generic isolation root `/source` falsely matched the legitimate Dart URI
  `package:audioplayers/src/source.dart`. A unique source mount was used for
  the rebuilt candidate, preserving the audit and the original failure log.

## Native review / reproducible next steps

On Windows with the workflow's Flutter SDK and MSVC/Cargokit prerequisites:

```powershell
python scripts/ci/build_flutter_with_privacy.py windows --release
# Run from repository root; wrapper owns apps/flutter cwd.
python scripts/ci/audit_artifact_privacy.py apps/flutter/build/windows/x64/runner/Release --diagnose --forbidden-root $PWD --forbidden-root $env:USERPROFILE
# Execute the workflow's VersionInfo, complete ZIP audit, plugin/FRB loading
# and ordinary-user application-startup checks on Windows, not via Linux mocks.
```

On macOS with Xcode and the workflow's Flutter SDK/Cargokit prerequisites:

```bash
python3 scripts/ci/build_flutter_with_privacy.py macos --release
app=apps/flutter/build/macos/Build/Products/Release/flutterustmusic.app
python3 scripts/ci/strip_macos_debug.py "$app"
python3 scripts/ci/audit_artifact_privacy.py "$app" --diagnose --forbidden-root "$PWD" --forbidden-root "$HOME"
codesign --verify --deep --strict "$app"
open "$app"
# Run the workflow's Info.plist, lipo, final ditto ZIP and privacy checks too.
```

These commands and guards are a review path, not claims of native execution.
A fresh hosted workflow requires Human-authorized publication of the candidate;
rerunning the old failed SHA cannot validate these uncommitted changes.

## Final scope and remaining work

Final review contains fourteen intended files: the workflow, Windows packaging
CMake flags, two AppImage fetch/test files, six Python audit/build/verification
files, one upstream fingerprint manifest and three progress/evidence docs.
There are no product Dart/Rust/Bridge/generated-code changes, native payload
deletions, blanket binary/HOME exemptions, warning-only gates, secrets or build
artifacts added to Git. Only this task's generated Python cache files were
moved to its temporary evidence directory; no pre-existing work was discarded.
Strict final APK/AppDir audits were rerun with the final checker. Linux and
Android are **FIXED / TESTED locally** within the named package checks, not
physical Android or real-account acceptance.

Machine-actionable work remaining:

- Windows: original failed DLL section/CodeView evidence and fresh MSVC final
  bundle/ZIP/metadata/FRB loading/startup. Blocker: no Windows/MSVC runtime here,
  and the old job did not upload the failed DLLs. Candidate flags are not proof
  of a fixed native binary.
- macOS: original failed first-party section evidence and fresh Xcode .app,
  Apple strip ABI checks, repaired ad-hoc seals, ZIP audit and startup. Blocker:
  no native macOS/Xcode here, and the old .app was not uploaded. The Linux LLVM
  corruption finding remains negative evidence, never an approved workaround.
- Hosted CI: complete run against this exact candidate. Human authorization is
  required to publish it or supply native artifacts; current instructions
  prohibit commit/push. No offline test can establish that remote result.
- Physical Android/network/audio/system-media and Linux FUSE acceptance remain
  **NOT VERIFIED**, beyond the proven package/static/no-FUSE startup boundary.

Execution mode: HUMAN_DIRECTED
Work domain: CI / Packaging / Artifact Security
Gate: HUMAN_REVIEW
