# Cross-platform package failure follow-up — 2026-10-25

Execution: `HUMAN_DIRECTED`; work domain: `CORE`. **Not complete:** native
Windows/macOS acceptance and the hosted AppImage namespace gate remain open.
The implementation phase performed no commit, push, merge, publication or
Actions rerun. Human subsequently authorized a local Git checkpoint; push and
new Actions runs remain unauthorized.

## Baseline, evidence and hypotheses

Task start was clean at `f50c987ff4ac60c6bc01ab7cb1360f62b4e4fa7c`.
[Run 40162179664](https://github.com/fura-project/fura-music/actions/runs/40162179664)
used `2cec96a5d94ec928cd2aebe64121324d46078222`. That revision was fetched
read-only into `FETCH_HEAD`, not checked out. Its only difference from local
HEAD is an unrelated QQ test line; packaging/build implementations are equal.
The existing origin URL was not changed. Authentication, Provider, Settings,
playback, Bridge and Dependabot code remain untouched.

All four failure logs and the AppImage build log were downloaded and read.
Raw logs, downloaded binaries, synthetic probes and trial results are outside
Git at `/tmp/fura-ci-40162179664-pb8oqo/`. Diagnostics below never reproduce
matched path strings, private symbols, Mach-O contents or account information.

| Platform / job | Observed failure | Hypothesis and evidence boundary |
| --- | --- | --- |
| Windows, 121076679002 | Build succeeds; privacy rejects the Rust DLL, 145 distinct `.rdata` offsets, each reported under both root-2 separator categories | Two confirmed build-chain gaps: missing Rust separator variants, and native C `__FILE__` outside Rust remapping. Locked AWS-LC's cl-like branch supplies no native prefix maps. Original DLL was not uploaded, so attribution of **all 145** occurrences to either source remains unproven. |
| macOS, 121076679024 | Build succeeds; native strip contract rejects before packaging, without naming the invariant | The old log cannot distinguish a real runtime change from a fingerprint problem. The `.app` was not uploaded. Do not presume either cause, or relax a guard to infer success. |
| Ubuntu AppImage, 121078260469; Fedora AppImage, 121078260520 | Namespace preflight fails at UID mapping, before extraction/audit/launch | Both report userns enabled, positive namespace limits and an unconfined profile; Docker already uses the three existing security-option exceptions. Exact kernel/LSM rejection is not proven without host policy/audit evidence. This is **ENVIRONMENT_BLOCKED**, not an AppImage startup result. |

The successful offline, Android, iOS Simulator, Linux package build/install
jobs in that run remain historical results for that SHA, not candidate passes.
Neither failed Windows DLLs nor a failed macOS app were retained as artifacts.

## Windows: source-map fix, native acceptance pending

`build_flutter_with_privacy.py` now maps **both** slash spellings of HOME and
source roots on Windows, preserving encoded arguments containing spaces,
repeated `-C`, source-after-HOME precedence, and `/PDBALTPATH:%_PDB%`.
This is compile-time path avoidance, not binary rewriting or an exemption.

The [Rust path-remapping documentation](https://doc.rust-lang.org/rustc/remap-source-paths.html)
specifies textual replacement without separator normalization. A real local
`rustc` fixture embeds `file!()` from a synthetic Windows-spelled source name:
the backslash-only map leaves the slash-spelled prefix, and both maps remove
it. The old wrapper also fails the new Windows-prefix coverage regression.

Final dependency audit found a second, independent source: the Windows-target
Cargo graph links `reqwest -> rustls -> aws-lc-rs 1.18.0 -> aws-lc-sys 0.44.0`
into the bridge. In the pinned source, `include/openssl/err.h` passes
`__FILE__` into `ERR_put_error`; `builder/cc_builder.rs` explicitly returns no
path-reproducibility options for cl-like drivers. Rust remapping and PDB
linker options cannot rewrite these native C runtime strings.
The three inspected dependency source files byte-match the cached crate
archive, whose SHA256 matches `Cargo.lock`; no registry source was modified.

The private Windows wrapper now selects `clang-cl` only through AWS-LC's
existing crate/target-scoped `HOST_CC` / `HOST_CFLAGS` controls and its cc
builder. It supplies `/clang:-ffile-prefix-map` for both root spellings,
retaining caller C flags and quoted spaces. `CC`/`CFLAGS` for other dependencies,
Flutter's MSVC toolset, the Rust MSVC target/CRT contract, crypto source,
TLS provider and cipher selection are not replaced. The `cc` crate's documented
shell-escaped flag parser is enabled to preserve those argument boundaries.
A missing `clang-cl` fails with a fixed category instead of silently compiling
unmapped source. The current
[Windows runner inventory](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)
lists LLVM; the actual native build still has to verify its configured tools.
[Clang documents](https://clang.llvm.org/docs/UsersManual.html#clang-cl) the
MSVC-compatible driver and forwarding of native Clang options; no undocumented
MSVC `/pathmap` or macro redefinition is introduced.

A real MSVC-target PE DLL fixture (cross-compiled/linked locally, no CRT or SDK
stub) embeds narrow and wide `__FILE__` in `.rdata`. Rust flags alone leave both
private-root strings and fail the **unchanged** audit. Native compiler maps
remove both and pass, preserving the stable mapped source name. This is real
PE/source-macro evidence, **not** a native Windows Fura/crypto runtime pass.

Cargokit's CMake/batch/Dart chain inherits the parent environment;
`RustBuilder.build()` passes `--target`, and `Process.runSync` keeps
`includeParentEnvironment=true`. Per the
[Cargo precedence contract](https://doc.rust-lang.org/cargo/reference/config.html#buildrustflags),
encoded flags outrank other rustflag sources. A real offline Cargo Release
cdylib fixture with a synthetic registry dependency and spaces in its path
confirms the target fingerprint records the exact flags and the compiled
library passes the strict path audit. This is Linux compiler evidence, **not
MSVC/Windows proof**.

After a Windows build the wrapper now requires a matching Cargo target
fingerprint for `rust_lib_flutterustmusic`, emitting fixed missing/invalid/
not-applied categories rather than paths or compiler arguments. AWS-LC's Cargo
build-script fingerprint must also record the selected compiler/maps/builder.
Old incremental
fingerprints can coexist; at least one exact flag-set fingerprint must exist.
This is additional compile evidence, not a substitute for auditing the DLL.
The separate final bundle **and ZIP** privacy checks remain mandatory.

Optional audit diagnostics add fixed `origin_hint` values for structurally
recognized CodeView PDB, Rust-registry and native C source-path occurrences.
`pattern_encoding` names the matching byte pattern, not proven string framing
(adjacent NULs can overlap). Unknown remains unknown. Hints do not approve any
byte or alter the rejection decision.

**Native status: NOT RUN.** There is no running authorized Windows/MSVC build
environment in this task. Existing personal Windows VMs were not booted or
modified. Next: native Release build, target-fingerprint verification, strict
DLL/bundle/ZIP audit, metadata, FRB/plugin loading and ordinary-user startup.
If a hit remains, use its section/category/origin hint to inspect its actual
compiler/dependency source without printing the matched bytes.

## macOS: diagnostic ownership fixed; underlying failure not yet resolved

`strip_macos_debug.py` compares the independent before/after properties and
reports fixed categories:

- `MACHO_FORMAT_OR_SLICES_CHANGED` / invalid format or slices;
- `LOADABLE_SECTIONS_CHANGED`;
- `LINKEDIT_OR_DYLD_CHANGED` / `LINKEDIT_OR_DYLD_INVALID`;
- `EXPORTED_SYMBOLS_CHANGED`;
- `CPU_ARCHITECTURES_CHANGED`;
- `DYLIB_DEPENDENCY_OR_INSTALL_NAME_CHANGED`;
- `DEBUG_METADATA_REMAINS`.

An ordinal identifies strip progress without exposing a source root or symbol.
Read/write errors are category-only. Non-ad-hoc signatures are still rejected
before mutation. Any contract failure prevents seal repair/packaging; only
affected ad-hoc seals are repaired inner-to-outer and strict codesign remains.
`macho_linkedit_fingerprint`, loadable fingerprints, symbol/alias validation,
dyld-data checks and `upstream_media_privacy.json` were **not weakened or
changed**.

The independent macOS media archive was downloaded again and matched SHA256
`84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6`.
All eight policy-listed Mach-O payload, loadable and LINKEDIT fingerprints
reproduce. Tests show STABS removal/string-table relocation preserves the
runtime fingerprint, while alias-target, weak-definition and dyld-binding
corruption remains rejected.
An additional failing regression found that a malformed universal slice extent
could be mislabeled as LINKEDIT failure. Container bounds/overlaps now classify
it as format/slice invalidity instead. All 18 framework containers in the
public archive pass those structural checks; this adds no upstream exception.

Retained negative experiment: Linux LLVM `strip -S` on the upstream Avcodec
preserves loadable bytes but creates an invalid indirect export. The guard
reports `LINKEDIT_OR_DYLD_INVALID`. This is **not evidence that Apple's native
strip has the same bug**, and LLVM is not a packaging substitute.

**Native status: NOT RUN. Underlying macOS fix: UNFINISHED.** No native
macOS/Xcode environment or original failed `.app` is available. The next native
run must collect the new category before choosing a tool/algorithm/build/signing
fix. A proven pure-debug semantic difference may justify a narrowly tested
normalization later; no such normalization was guessed here.

## AppImage: separate environment failure and verified launcher defect

### Hosted namespace boundary

`probe_appimage_sandbox.py` runs only as an ordinary user, rejects an explicit
WebKit-sandbox bypass, bounds the actual bubblewrap probe to 15 seconds, and
reports fixed `ENVIRONMENT_BLOCKED` categories for UID/GID mapping, other
namespace failure, timeout or missing tool. Only numeric policy/capability
diagnostics are printed. Success explicitly says application launch is **not
yet tested**. A blocked prerequisite still fails the workflow; there is no
allow-failure, skipped startup promoted to pass, or further privilege grant.

The workflow checks out this script before using it. Existing Docker options
were not expanded. The old logs do not include the AppArmor userns policy or a
host kernel audit denial, so blaming a specific LSM remains a hypothesis.
[Ubuntu's security explanation](https://discourse.ubuntu.com/t/understanding-apparmor-user-namespace-restriction/58007)
distinguishes allowing namespace creation from capabilities inside it; an
`unconfined` string and positive limits alone cannot prove mappings will work.

### Runtime defect discovered after the preflight boundary

The original AppImage artifact was downloaded, checksum-verified and extracted.
SHA256: `8c2d5e68245d2ca480640f90a7b3d2cf0d3ea87bab86bd342a6a4a831de65051`.
It passes its original checkout-root/HOME privacy audit and creates real X11
windows in isolated Ubuntu 24.04 and Fedora 43 userspaces on this Linux host.

A stricter offline WebKit probe then found a real packaging defect hidden by
window-only smoke: AppRun's shallow symlink view routes helpers and system
libraries through a temporary host-root alias. WebKit's second sandbox root
does not contain those symlink targets. The old launcher fails helper rebind
and/or ELF-loader execution before the local page can load.

`packaging/linux/assets/AppRun` now builds a real mount skeleton in a private
namespace, read-only binds the original host-library entries and packaged
helpers to their standard destinations, and remounts the skeleton read-only.
It does not write host `/usr/lib`, copy/patch ELF bytes, disable sandboxing,
add capabilities, or expose a second temporary host-root alias. `/tmp`, HOME
and runtime-directory writable bindings retain their previous scope.

The new offline launcher test fails against pre-task AppRun and passes the
candidate. Real bubblewrap 0.9 (Ubuntu) and the Fedora target were also used.
A minimal GTK/WebKit widget explicitly enables sandboxing and loads only
synthetic in-memory HTML with networking isolated. The old launcher reproduces
failure; the candidate completes the page on both targets. WebProcess is
observed with `Seccomp=2`, `CapEff=0`. No stored account/login request is used.

### Second runtime defect: missing MIME data

The retained MiniBrowser pixbuf crash was not dismissed. A controlled probe
found that the original AppDir lacks `usr/share/mime/mime.cache`: GTK cannot
recognize even its embedded PNG resource in the declared minimal targets.
The same probe fails with exit 5 before page loading without MIME data, then
decodes the resource and loads the sandboxed page after adding **only** a
generated database from the standard `shared-mime-info` definitions.

The existing packaging helper now stages that one package-owned XML and
generates its cache. AppImage build prerequisites explicitly include the tool;
artifact audit rejects missing/empty caches; system-notice collection includes
the definition's owning package/copyright. No GTK runtime package or MIME
database was installed into the clean target bases to hide the omission.
Tests cover actual cache generation, successful tool exit without a cache,
and rejection before ELF inspection. The exact earlier MiniBrowser toolbar
case also passes on both targets after this data fix, with sandboxing enabled.

A first local candidate was repacked with the same pinned appimagetool/runtime,
reusing the CI Release payload and replacing only its launcher from current
source. That intermediate, pre-MIME candidate is retained for comparison:
SHA256: `42412b7f303c7107fddfbe327502b0e7ef681770675625c53d1124285a30e078`.

The **final** local repack includes the MIME data and its package notice,
preserving all original ELF payloads and their notices. SHA256:
`2b67598c20a47a57f396128239b8dd3d4b6db867a69cfc85c8af254eb751b829`.
It is **not** a fresh Flutter/Rust build or published artifact.
The final candidate was extracted again: strict original-root/HOME privacy
passes; both target userspaces resolve all 440 ELFs, with maximum GLIBC 2.39
and GLIBCXX 3.4.32, and both create an actual X11 window with the AppDir mounted
at a path containing spaces. GTK PNG decoding, sandboxed local HTML and the
MiniBrowser toolbar pass on both targets. Reports are in
`mime-final-ubuntu-audit/`, `mime-final-fedora-audit/`, `mime-final-privacy.log`
and the corresponding `mime-final-*.log` files in the temporary evidence
directory. These share the local host kernel; the native CI namespace gate
is still open.
The final extracted `AppRun.wrapped` byte-matches the current source. A further
strict scan including the temporary task and MIME-generator build roots also
passes (`mime-final-all-build-roots-privacy.log`); it does not erase the separate
exploratory flite finding below.

Retained additional negative evidence:

- An initial test mountpoint was absent under a read-only root; moving harness
  mounts beneath its tmpfs fixed that harness prerequisite.
- Fedora initially had a mismatched test HOME/D-Bus inotify warning. Repeating
  with a fresh writable home at the test user's passwd location removes it.
- The first WebKit harness omitted sysfs; read-only sysfs supplies that normal
  Linux runtime prerequisite, without changing host policy.
- A symlinked synthetic test AppDir and a non-executable baseline test copy
  caused distinct harness failures; both were corrected before the controlled
  old/new minimal-widget comparison.
- The original MiniBrowser toolbar pixbuf/icon crash and the isolated missing-
  MIME resource failure remain recorded as **pre-fix** negative evidence.
  The final data fix passes both the exact toolbar case and the resource probe;
  this does not prove every login, accessibility-service or multimedia state.
- An extra exploratory `/__w` scan (not either original forbidden root) finds
  a third-party flite payload. No exemption was added. Both original root
  checks remain strict and passing; the exploratory result is not erased.

### Implementable safe CI topology (provisioning required)

Do not keep escalating Docker capabilities or disable WebKit/AppArmor/SELinux.
Use two dedicated ephemeral native VMs, with independent Ubuntu 24.04 and
Fedora 43 kernels and the existing declared minimal base/harness packages.
Do not preinstall GTK/WebKit/mpv/GStreamer/libsecret to hide packaging gaps.
Register the VMs only for trusted manual jobs with labels such as
`fura-appimage-ubuntu24` and `fura-appimage-fedora43`; discard each VM and disk
after one run. Do not reuse a maintainer's personal desktop/account session.

The existing verification job's steps can be retained with this topology:

```yaml
runs-on: ${{ matrix.runner }}
strategy:
  fail-fast: false
  matrix:
    include:
      - name: Ubuntu 24.04
        runner: [self-hosted, Linux, X64, fura-appimage-ubuntu24]
      - name: Fedora 43
        runner: [self-hosted, Linux, X64, fura-appimage-fedora43]
# Remove container and container_options. Provision the declared base in the
# disposable VM image; run probe and application as an ordinary test user.
```

Before accepting a VM: record distro/kernel/policy, run the same strict
namespace probe under distribution-supported sandbox policy, verify clean base
packages, download the exact trusted source-run artifact, verify its checksum,
extract/audit every ELF and privacy root, and run the actual X11-window gate.
An offline WebKit widget gate should additionally confirm sandboxed helper
startup. Fail any unavailable prerequisite; never infer a pass from a file.
This topology was **not** silently activated on unprovisioned runner labels.
The authorized admin must supply those ephemeral runners (or equivalent safe
native runners) before native CI acceptance. Current hosted result remains
`ENVIRONMENT_BLOCKED`, not proven impossible on every hosted topology.

## Validation and remaining acceptance

The final 14-file code/config snapshot (all changed tracked and untracked
non-Markdown files, sorted relative name + NUL + bytes + NUL) has SHA256
`a83a17a6bfb0eda293425b93cf5ca6fe74a238d0bc67b095929abc0f56de3f3e`.
At the implementation handoff, HEAD remained
`f50c987ff4ac60c6bc01ab7cb1360f62b4e4fa7c` and no files were staged.

Local checks include the privacy suite (32 tests), sandbox failure-classification
suite (4 tests), AppRun/audit regressions (2 tests), real rustc/Cargo fixtures,
AppImage transport/pin tests, packaging helper/normalization/ELF-dependency
tests, ShellCheck 0.11.0, actionlint 1.7.12 (including embedded ShellCheck),
67 embedded Bash syntax checks, Rust format, Dart format (304
files)/analysis, source privacy/identity, and whitespace checks. No Dart/Rust
production source or Bridge contract changed. `cargo test --locked -p
rust_lib_flutterustmusic --lib` also passes all 115 Linux Bridge unit tests;
`cargo clippy --locked -p rust_lib_flutterustmusic --all-targets --no-deps -- -D
warnings` passes the affected Bridge targets without changing unrelated
workspace test-only lint findings;
no generated-code or whole Flutter/Rust test-suite pass is inferred from these
scoped checks, nor do Linux tests prove the new Windows native C build.

Preserve environment trials: host normalization tests initially lacked `jq`;
the Ubuntu builder run initially omitted `ldconfig` from PATH. Tests were
rerun using the installed builder prerequisites and normal sbin PATH, without
weakening assertions or installing packages into the maintainer host.

Remaining work:

1. Native Windows Release DLL and ZIP audit/loading/startup; verify actual
   Cargo flags and resolve any remaining occurrence from its generating source.
2. Native macOS classified failure, then verified fix and strict .app/ZIP,
   signatures, architecture, dependencies, exports and startup. This branch is
   explicitly unfinished, not a successful fix based on diagnostics alone.
3. Provision/authorize the safe native AppImage runner topology, then run the
   exact candidate through CI. Local userspace/host-kernel passes do not prove
   the failing GitHub Docker environment, a guest kernel or FUSE mounting.
4. Pushing/publishing the candidate or starting a new remote Actions run needs
   Human authority; the subsequent local-checkpoint request does not perform
   those remote actions.
