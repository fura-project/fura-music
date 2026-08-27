# Technical Debt

Technical debt is reviewed after each finite task. States are `Open`, `Triggered`, `Scheduled`, `In Progress`, `Resolved`, and `Accepted Permanently`.

## TD-001 — System-Rust bridge builds bypass Cargokit

**Status:** Open

**Problem:** `flutter_rust_bridge` 2.13.0 generates a Cargokit backend that invokes `rustup` unconditionally. The Arch development environment intentionally uses supported system `rustc` and `cargo` packages, where installing rustup would conflict with the system toolchain. Linux x64 therefore has a small direct-Cargo CMake integration. Android uses a project-owned Gradle task only on Linux hosts without `rustup`; it accepts one explicit ARM64 or x64 target, builds the matching standard library from the distribution `rust-src` package, and otherwise leaves generated Cargokit in place.

**Why accepted:** Linux is first-class and the direct build uses the same Cargo workspace, lockfile, crate type, and Rust compiler already validated by the core suite. Replacing the whole bridge or installing a conflicting toolchain would be larger and riskier during the executable-foundation task.

**Impact:** The Linux CMake and Linux-host Android Gradle integration are no longer fully generator-owned. Android system-Cargo support is deliberately limited to one explicit ARM64 or x64 build. Matching system `rust-src` is installed; a clean release ARM64 build compiled `std` from it, produced a complete single-ABI APK, passed 16 KB alignment/signature checks, and started under the AVD's ARM64 translation. Native x64 packaged FFI passed on Android 16.

**Risk:** Re-running bridge integration could overwrite the customization; other Android ABI sets and non-Linux target builds still need verified toolchain paths. Future dependency changes could reintroduce incomplete ABI advertising or compiler-runtime symbols unless the current guards remain. Emulator and translation success do not prove physical-device behavior.

**Suggested solution:** Adopt upstream Cargokit/native-assets system-Rust support when it can replace the two localized paths without losing the current Cargo lockfile, NDK API 24 toolchain, target-aligned ABI filtering, NDK compiler-runtime linkage, unresolved-symbol gate, or 16 KB page alignment. Add another ABI only when a Roadmap or runtime target requires it.

**Trigger condition:** The Android ARM64 build and x64 emulator triggers were handled on 2026-08-26. Reassess when FRB/Cargokit gains supported system-Rust builds, regeneration overwrites either customization, or another target/ABI becomes required.

## TD-002 — Release identity and signing use generated defaults

**Status:** Triggered

**Problem:** Platform shells still use Flutter-generated application branding and development signing defaults. Android release builds currently use the debug signing configuration.

**Why accepted:** Development builds were needed to prove the in-process architecture and target packaging without distributing binaries. Inventing release identity, signing custody, and store metadata would expand scope and introduce credential risk.

**Impact:** Locally built artifacts are development artifacts only and must not be published as releases.

**Risk:** An accidental release build could look production-like while carrying development identity or debug signatures.

**Suggested solution:** After HD-001 is decided, define project-owned application icons, display names, identifiers, and a secret-safe per-platform signing workflow.

**Trigger condition:** Triggered on 2026-08-26 when M1 packaging produced and inspected Android ARM64/x64 APKs and continued Linux release bundles. No artifact has been authorized for external distribution. Resolution is locally blocked on HD-001; unrelated development continues.

## TD-003 — Persisted credential restore lacked server verification

**Status:** Resolved

**Problem:** `QQMusicProvider` serialized a successful credential into a versioned opaque document and startup imported it, but a structurally valid candidate was not verified with QQ Music. Closing the application therefore could not regain an authenticated session safely.

**Why accepted:** Persistence, local import, and network verification are separate failure domains. The staged local slice first proved absence, corruption, format version, invariant validation, and expiry behavior without allowing a stored key to imply server validity; the UI reported verification as pending until this network step was implemented.

**Impact:** Resolved for the implemented path: an eligible stored candidate now reaches authenticated state only after QQ Music accepts it. The platform vault runtime and real-account acceptance gaps remain TD-004 and a documented validation risk respectively.

**Risk:** Future error mapping could regress by treating a transient failure as rejection, or stale verification could overwrite a replacement login.

**Suggested solution:** Implemented with the named user-info RPC, exact attempt IDs, explicit rejection-code mapping, retained transient failures, and cross-layer regression tests. Secure storage is deleted only at the Flutter platform edge after explicit rejection.

**Trigger condition:** Resolved on 2026-08-25. Reopen if QQ Music response evidence changes, a transient failure signs the user out, or a stale verification can promote after replacement/cancellation.

## TD-004 — Secure-storage runtime behavior is not verified on every target

**Status:** In Progress

**Problem:** Linux and Android 16 x64 now have passing disposable write/read/delete integrations. iOS, macOS, and Windows implementations have not been built or run in this checkout.

**Why accepted:** The Linux test uses an isolated randomized non-account key, never calls `deleteAll`, and confirms absence in `finally`. Not every other target runtime is available on this host, and claiming runtime verification from generated registrants would be false.

**Impact:** Linux's configured adapter and Android's x64 emulator path are runtime-verified on this host. An unverified target may still have an entitlement, keyring, or plugin issue that leaves the user authenticated only for the current process; the UI reports that failure without discarding the active Rust credential.

**Risk:** A non-Linux build could appear to support restart restore while its platform vault is inaccessible, or future changes could weaken the disposable test's cleanup boundary.

**Suggested solution:** Reuse the disposable non-account round-trip pattern on each target before that target is accepted for authenticated distribution; keep unique keys and guaranteed cleanup instead of broad vault deletion.

**Trigger condition:** Linux was resolved on 2026-08-25 and the Android M1 instance on 2026-08-26. Apple and Windows targets must resolve their own instances before their distribution.

## TD-005 — Favorite-playlist aggregation has a 1,000-row safety ceiling

**Status:** Open

**Problem:** The complete QQ Music playlist operation follows at most ten favorite pages of 100 rows. If QQ Music still reports `hasmore`, the Provider returns `InvalidResponse` instead of continuing indefinitely or silently returning a partial library.

**Why accepted:** QQ Music is an unstable external service, yakult's current implementation independently uses the same 1,000-row ceiling, and this checkout has no sanitized evidence for accounts exceeding it. A finite bound is required before the loop can sit behind one cancellable Bridge operation.

**Impact:** An account with more than 1,000 favorited playlists cannot load the combined library, although its created-only operation remains available internally.

**Risk:** The UI may show a structural-response error for a legitimate unusually large account.

**Suggested solution:** Replace the fixed aggregate call with an evidence-backed higher bound or incremental user-library pagination that keeps cancellation and account-replacement checks exact. Never silently truncate.

**Trigger condition:** Reassess when a sanitized fixture or controlled integration returns `hasmore` after page ten, or before public alpha if large-library support becomes an acceptance requirement.

## TD-006 — Native video distribution notices are not assembled

**Status:** Open

**Problem:** M5.5 adds the MIT-licensed `media_kit` packages and their bundled native playback libraries. Development builds intentionally do not yet contain a project-owned, per-platform inventory and notice bundle covering the exact libmpv/FFmpeg build flavor and all applicable native-library terms.

**Why accepted:** The dependency decision used the upstream default non-GPL video flavor and bounded local Linux/Android packaging evidence. No artifact is authorized for external distribution while HD-001 remains pending, so assembling production notices before the final artifact shape and release ownership exist would be premature.

**Impact:** Development and testing can continue, but an MV-capable binary must not be published as a release until its exact native dependency inventory and required notices/source or relinking information have been reviewed and included.

**Risk:** Publishing without that review could omit license text or another obligation imposed by the native media stack. Dependency updates could also change the bundled build flavor or license set without an obvious Dart API change.

**Suggested solution:** During authorized release preparation, inventory each platform artifact, verify the selected native build configuration against upstream provenance and licenses, include the required third-party notices and corresponding source/relink information, and add a repeatable release check that detects dependency or build-flavor changes. Obtain human/legal guidance if the applicable distribution terms remain uncertain.

**Trigger condition:** Schedule together with TD-002 after HD-001 is resolved and before the first external MV-capable artifact is distributed; reassess immediately if the media packages or native build flavor change.

## TD-007 — Remote library mutations duplicate single-use lifecycle adapters

**Status:** Open

**Problem:** Liked-Track and owned-playlist Track membership deliberately use two explicit Bridge handles and Dart gateways with nearly identical single-use cancellation, typed unknown-outcome, and credential-cleanup mechanics.

**Why accepted:** Two concrete operations established the real common lifecycle while keeping their desired-state types and Provider contracts clear. A generic remote-mutation framework before that evidence would have been speculative and harder to audit for account safety.

**Impact:** Failure mapping and cancellation rules currently need parallel updates in two narrow files.

**Risk:** A third copied mutation path could drift by reporting an uncertain remote write as a definitive failure, retrying it, or clearing credentials for a non-rejection.

**Suggested solution:** When a third distinct remote library mutation is selected, extract only the proven single-use lifecycle and credential-cleanup mechanics while preserving operation-specific typed inputs/results and Provider-owned identity parsing.

**Trigger condition:** The third distinct remote library mutation enters implementation.

Each future item must record: ID, status, problem, why accepted, impact, risk, suggested solution, and trigger condition. Source TODOs should reference the corresponding ID where practical.
