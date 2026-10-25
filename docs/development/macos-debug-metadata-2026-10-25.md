# macOS Release debug-metadata follow-up — Run 30

Execution mode: `HUMAN_DIRECTED`; domain: `CORE`.
Status: **CODE_FIX_CANDIDATE_VERIFIED_OFFLINE / NATIVE_MACOS_CI_NOT_RUN**.
This is not native Release acceptance or whole-platform completion.

## Baseline and evidence boundary

The worktree was clean at `3d2f4c27a09a29bfccd366a128f62ab5f1d504c1`.
After inspecting the remote-only changes, it was fast-forwarded to the Human's
reference `f2388203d7251f6f57566a0d20f74542796bab63`. Those baseline changes
only update existing action pins; this task does not change those pins.

[Run 40188843560](https://github.com/fura-project/fura-music/actions/runs/40188843560),
macOS job `121156289210`, builds the 137.3 MB Release app successfully, then
fails at `MACHO_STRIP_BEGIN: binary_index=1` with only
`DEBUG_METADATA_REMAINS`. Packaging/upload are skipped; the failed app is not
an available artifact. The log does not establish which component owns that
ordinal or whether its residual record is DWARF or STABS. It is not evidence
of damaged code, exports or binding data.

Raw logs, fetched public source, synthetic producer experiments and test output
are outside Git at `/tmp/fura-macos-debug-40188843560-axNj8Y/`. No private
symbols, matched paths, binary dumps, credentials or account operations were
used as diagnostics. No remote Actions run was started.
The four-file code/config snapshot (changed non-Markdown files, sorted relative
name + NUL + bytes + NUL) is SHA256
`8de410383d42cbe06a7c541341a1a07e7b06c2d589be578cf8b1a0fc4ec31586`.

## Confirmed detector defect, not a need for stronger stripping

The old predicate treats **every** `n_type & N_STAB` record as source debug
metadata. Apple's own `strip` deliberately synthesizes a compatibility record
when an indirect-symbol table needs a nonzero first external-symbol index.
It uses an `N_OPT` record and therefore has those mask bits even after `-S`.

Primary evidence is Apple's cctools revision
`e0d56624eca2a76c2ace4c21850df9e666de4ca5`:

- [strip implementation](https://github.com/apple-oss-distributions/cctools/blob/e0d56624eca2a76c2ace4c21850df9e666de4ca5/misc/strip.c),
  the radar-5614542 local-symbol workaround and its synthesized record;
- [Apple strip manual](https://github.com/apple-oss-distributions/cctools/blob/e0d56624eca2a76c2ace4c21850df9e666de4ca5/man/strip.1),
  the `-S` symbol-removal contract and indirect-table adjustment;
- [Apple nlist format](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/nlist.h),
  the 64-bit record layout and `N_STAB` mask.

The candidate recognizes only the full fixed record: `N_OPT=0x3c`, section zero,
description zero, value `0x05614542`, exact NUL-terminated `radr://5614542`,
at the first local record with a declared nonempty indirect table. Other
`N_OPT`, `N_OSO`, STABS and any nonempty DWARF section still count as debug.
Malformed indirect targets are independently rejected. The marker is never
removed, rewritten or added by Fura.

This is reproducible on **real independently downloaded upstream binaries**,
not only a constructed fixture. The existing media archive rechecks to SHA256
`84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6`.
Of its 18 Mach-O files, six contain only the exact compatibility marker,
nine contain actual STABS and three contain neither. The old detector rejects
the six marker-only binaries. The candidate clears those six and continues
to detect the nine real-debug files. The pinned Avcodec payload is one of the
proven marker-only cases. All eight committed macOS payload, loadable and
LINKEDIT fingerprints reproduce without changing the policy file.
The unmodified pinned Avcodec binary also passes the existing strict workspace/
HOME privacy audit, while the old debug predicate still rejects it. Its removal
from the strip candidate set is not a new privacy exemption.

The first newly added regression fails against the old predicate and passes
with the fix. This proves an actual packaging-detector defect and a reachable
reason that repeated `-S` cannot satisfy the old requirement. The missing
Run-30 app still prevents claiming the exact historical first object's
identity; native acceptance must confirm that there is no additional residual
DWARF or another real STABS case after this correction.

## Compiler and Apple tool semantics

`strip -S` targets debugging symbol-table entries, not a general guarantee to
erase arbitrary DWARF sections from every linked image. The examined Apple
implementation delegates DWARF stripping of `MH_OBJECT` files to the linker;
this is different from making all linked-image `__DWARF` data disappear.
No `-x`, `-s`, `-N` or LLVM replacement was added to the production command.
If genuine DWARF remains, the candidate still refuses packaging.

The installed Flutter 3.47.1 producer uses `--macho-object` alongside the AOT
dylib, extracts a dSYM and invokes its own Apple symbol stripping. The matching
Dart SDK revision `852b3e3608906afbe6102573cfd4407aeedd1b78`
[Mach-O writer](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/runtime/vm/mach_o.cc)
puts DWARF in the separate object when one is supplied, and keeps a debug map
in the linked snapshot. The first-party AOT producer, Runner/source-built
plugins, Rust framework, prebuilt Flutter engine and prebuilt media frameworks
are separate build origins; a global Xcode setting is not proof of how every
prebuilt framework was produced.

A local, synthetic Dart producer comparison confirms the format distinction:
the paired dylib has STABS, its separate object has DWARF, and the no-object
control has both. These are **Linux-hosted format experiments**, not an Apple
strip, macOS load or signing pass. An initial ordinary-kernel input aborted
because it lacked the AOT preparation; rerunning through the documented
`gen_kernel --aot` producer completes both controls. That initial failure is
retained in the temporary logs, not silently called a pass.

[Apple's build-setting reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
separates `DEBUG_INFORMATION_FORMAT` (including dSYM output),
`COPY_PHASE_STRIP` (copied binaries), `STRIP_INSTALLED_PRODUCT` and
`DEPLOYMENT_POSTPROCESSING` (linked-product postprocessing), and `STRIP_STYLE`
(the removal level). Existing Release configurations already request
`dwarf-with-dsym`; the macOS privacy wrapper already supplies copy/deployment
stripping. Neither those settings nor the wrapper are changed: they cannot
fix the demonstrated predicate error. dSYM/object/debug-sidecar outputs must
remain outside the delivered app/ZIP and must not be uploaded with private
build roots. Debug content accidentally embedded in the app still fails.

The current Linux host has no `xcrun` or authorized Xcode runtime. Run 30 did
not record an explicit selected-Xcode version alongside the failure; the
examined cctools source is evidence of the documented marker, not a claim
that its revision is the precise tool binary used by that runner.

## Implementation and unchanged protections

`strip_macos_debug.py` now reports per-slice architecture categories and
separate DWARF/STABS booleans, before/after fixed state names and runtime
contract result categories. It never prints candidate filenames, paths,
symbol names or native tool output. Successful strip progress is ordinal-only.
Thin and universal slices are checked independently; malformed slice bounds
fail closed. Unsupported Mach-O encodings fail closed rather than being
silently treated as a clear 64-bit image.

Existing format, loadable-section, LINKEDIT/dyld, exports, CPU and install-name/
dependency guards remain. A separate `macho_indirect_fingerprint` also covers
`LC_DYSYMTAB` targets: renumbered indexes resolve to the same symbol meaning,
whereas changed targets, invalid indexes or a target into a debug record fail.
Its addition does not alter the pinned LINKEDIT hash format or upstream policy.
Original `macho_linkedit_fingerprint` hash semantics remain unchanged, with
shared validated slice extraction. Export-trie and chained-fixup byte changes
remain rejected.

Processing now uses a private same-filesystem app copy with preserved relative
framework symlinks. All affected seals must be ad-hoc **before any strip**,
checked separately for every architecture. Native `codesign` display otherwise
defaults to the host slice, while signing affects every slice, as documented
in [Apple TN3126](https://developer.apple.com/documentation/technotes/tn3126-inside-code-signing-hashes).
Bundle primary executables are resolved from their checked Info.plist metadata;
native `lipo` supplies the actual architecture names, not a guessed profile.
Signature identity matching requires a complete `Signature=adhoc` output line,
not a substring in an executable path. Canonical-marker-only binaries are not
stripped or re-signed. Broken/external symlinks are rejected before tools run.

After strip contracts pass, affected seals are repaired inner-to-outer using
the existing identifier/entitlements/requirements/flags/runtime preservation
options. There is no `--deep` signing. Strict deep verification and a second
runtime-contract check must pass before installing the copy. The final installed
path is strictly verified again before discarding the original backup. This follows
[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
on nested signing and executable changes; it does not authorize Developer ID
or other non-ad-hoc third-party re-signing.

Strip, metadata, signing or final-verification failure leaves the original
tree unchanged. Replacement failure or a handled interruption restores it.
If restoring the original itself fails, the private backup is retained and a
fixed error is emitted. A hard process kill during replacement/final verification cannot
run Python rollback; the original remains under the private
`.fura-macos-debug-*/backup/` directory beside the app and must be recovered
locally before retry. Such a failure never permits packaging, and backups are
not public artifacts. No in-place binary patching is performed.

## Regression and native gate

The deterministic suite covers:

- DWARF-only, STABS-only, mixed and clear states, thin and universal;
- exact marker recognition; altered type/section/description/value/name/context
  and source-path-bearing content still rejected;
- real debug removal versus retained compatibility metadata;
- stable runtime meanings across symbol-table index changes;
- code, exports/N_INDR aliases, indirect targets, dyld binding, export trie
  and chained-fixup corruption;
- real-signature refusal, including deceptive output substrings and a signed
  non-host slice inside an otherwise ad-hoc universal image;
- invalid or malformed bundle executable metadata is rejected with a fixed
  category before tool mutation, without exposing parser errors or values;
- unchanged source bundle/seals/symlinks after each strip/sign/verify/install
  failure and interruption; retained private backup on failed rollback;
- inner-before-outer signing, strict verification, and post-sign runtime checks;
- no strip/re-sign for marker-only images, with final signature verification;
- fixed diagnostics without paths or symbol names; prior privacy/identity rules.

Old pseudobinary signing tests were upgraded to structurally complete Mach-O
fixtures; their behavior assertions were retained and strengthened with source
rollback checks. No failing behavior assertion was weakened.

`test_native_macos_debug_strip_sign_load_and_zip_privacy` is a real native test,
not a simulated success. On Darwin it compiles a synthetic universal executable
and framework with Apple clang, signs ad-hoc, runs the production preparation,
checks runtime contracts and strict signatures, executes the runner, loads the
framework, and audits both app and `ditto` ZIP. On Linux it explicitly skips as
`NATIVE_MACOS_CI_NOT_RUN`. Missing Xcode on Darwin is a failure, not a skip.
The existing macOS job now runs this small gate before its Release build;
other jobs, pins, privacy gates and artifact paths are unchanged.

Executed locally:

```sh
python3 scripts/ci/test_privacy_audits.py -v
python3 scripts/ci/audit_privacy_hygiene.py
python3 scripts/ci/verify_application_identity.py
python3 -m py_compile scripts/ci/strip_macos_debug.py scripts/ci/native_artifact_sections.py scripts/ci/test_privacy_audits.py
actionlint .github/workflows/cross-platform-development-packages.yml
git diff --check
```

The privacy suite passes **47 deterministic tests**, with **one additional
native-only test skipped** (48 total). Source privacy/identity, Python compile,
actionlint with ShellCheck, and whitespace checks pass. Independent archive
checks preserve all eight committed macOS fingerprints. The prior LLVM-strip
indirect-export corruption remains rejected; LLVM is not used as Apple proof.
The repeatable task-local archive/producer checker and its output are
`verify_macos_upstream.py` and `upstream-and-producer-evidence.log` in the
temporary directory; `privacy-tests.log` contains the final deterministic
results and explicit native-only skip. These evidence files are not Git input.
No Rust/Dart/Bridge production source changed, so no generated-code, whole
Flutter suite or Windows/Linux build pass is inferred from this task.

## Exact remaining native acceptance

On a clean authorized macOS/Xcode checkout of this candidate:

```sh
xcodebuild -version
python3 scripts/ci/test_privacy_audits.py \
  PrivacyAuditTests.test_native_macos_debug_strip_sign_load_and_zip_privacy
(cd apps/flutter && flutter pub get)
python3 scripts/ci/build_flutter_with_privacy.py macos --release
app=apps/flutter/build/macos/Build/Products/Release/flutterustmusic.app
python3 scripts/ci/strip_macos_debug.py "$app"
python3 scripts/ci/audit_artifact_privacy.py "$app" --diagnose \
  --forbidden-root "$PWD" --forbidden-root "$HOME"
mkdir -p apps/flutter/build/test-packages
ditto -c -k --sequesterRsrc --keepParent "$app" \
  apps/flutter/build/test-packages/flutterustmusic-macos-development.zip
python3 scripts/ci/audit_artifact_privacy.py \
  apps/flutter/build/test-packages/flutterustmusic-macos-development.zip \
  --forbidden-root "$PWD" --forbidden-root "$HOME"
```

The production script captures `nm`, `lipo`, `otool` and strict `codesign`
verification internally rather than logging raw filenames/symbols/tool output.
The existing workflow's identity and architecture checks still apply. The
native fixture's load pass is not a substitute for loading the full Release
application in a disposable account/session with no stored credentials.

No native fixture, actual Release build/strip/sign/load, or final Release ZIP
audit was executed here: **NATIVE_MACOS_CI_NOT_RUN**. Actual first-failure
component attribution, selected-Xcode behavior and final artifact acceptance
remain open. The implementation phase performed no Git publication or remote
Actions run. Human subsequently authorized a normal Git checkpoint and push;
this does not imply native acceptance or authorize a manual full workflow run.
