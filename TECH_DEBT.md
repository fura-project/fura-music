# Technical Debt

Technical debt is reviewed after each finite task. States are `Open`, `Triggered`, `Scheduled`, `In Progress`, `Resolved`, and `Accepted Permanently`.

## TD-001 — Linux bridge build bypasses Cargokit

**Status:** Triggered

**Problem:** `flutter_rust_bridge` 2.13.0 generates a Cargokit backend that invokes `rustup` unconditionally. The Arch development environment intentionally uses supported system `rustc` and `cargo` packages, where installing rustup would conflict with the system toolchain. Linux therefore has a small direct-Cargo CMake integration while other platforms retain generated Cargokit integration. The first Android build additionally cannot reach Cargokit because Flutter 3.47.1's Gradle plugin loader rereads a non-ASCII `flutter.sdk` path through Java's Latin-1 `Properties.load(InputStream)` behavior.

**Why accepted:** Linux is first-class and the direct build uses the same Cargo workspace, lockfile, crate type, and Rust compiler already validated by the core suite. Replacing the whole bridge or installing a conflicting toolchain would be larger and riskier during the executable-foundation task.

**Impact:** Linux's `rust_builder/CMakeLists.txt` is no longer fully generator-owned, and no Android APK has been produced in this checkout. Changing only the project settings reader is insufficient because the applied Flutter plugin reads the same file again.

**Risk:** Re-running bridge integration could overwrite the customization; other targets still need their own verified toolchain path.

**Suggested solution:** First give the Flutter tool an ASCII SDK root without moving or patching the external SDK, then observe the actual Android Cargokit failure. Adopt upstream Cargokit/native-assets system-Rust support when available, or add the smallest project-owned Android system-Cargo path only after that evidence identifies the required targets and NDK variables.

**Trigger condition:** Triggered on 2026-08-26 when M1 reached its first mobile build task. Three ARM64 release attempts stopped at the Flutter Gradle loader's corrupted SDK path; do not repeat the same invocation until the SDK root strategy changes.

## TD-002 — Release identity and signing use generated defaults

**Status:** Open

**Problem:** Platform shells still use Flutter-generated application branding and development signing defaults. Android release builds currently use the debug signing configuration.

**Why accepted:** The current task proves the in-process architecture and does not distribute binaries. Inventing release identity, signing custody, and store metadata would expand scope and introduce credential risk.

**Impact:** Locally built artifacts are development artifacts only and must not be published as releases.

**Risk:** An accidental release build could look production-like while carrying development identity or debug signatures.

**Suggested solution:** Define project-owned application icons, display names, identifiers, and a secret-safe per-platform signing workflow.

**Trigger condition:** Before any artifact is distributed outside development, or when M1 starts packaging work.

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

**Problem:** Linux now has a passing disposable write/read/delete integration against the current user's Secret Service. Android, iOS, macOS, and Windows implementations have not been built or run in this checkout.

**Why accepted:** The Linux test uses an isolated randomized non-account key, never calls `deleteAll`, and confirms absence in `finally`. Not every other target runtime is available on this host, and claiming runtime verification from generated registrants would be false.

**Impact:** Linux's configured adapter is runtime-verified on this host. An unverified target may still have an entitlement, keyring, or plugin issue that leaves the user authenticated only for the current process; the UI reports that failure without discarding the active Rust credential.

**Risk:** A non-Linux build could appear to support restart restore while its platform vault is inaccessible, or future changes could weaken the disposable test's cleanup boundary.

**Suggested solution:** Reuse the disposable non-account round-trip pattern on each target before that target is accepted for authenticated distribution; keep unique keys and guaranteed cleanup instead of broad vault deletion.

**Trigger condition:** The Linux instance was resolved on 2026-08-25. Each other target must resolve its own instance before distribution, and at least one mobile target must be verified before the M1 checkpoint.

## TD-005 — Favorite-playlist aggregation has a 1,000-row safety ceiling

**Status:** Open

**Problem:** The complete QQ Music playlist operation follows at most ten favorite pages of 100 rows. If QQ Music still reports `hasmore`, the Provider returns `InvalidResponse` instead of continuing indefinitely or silently returning a partial library.

**Why accepted:** QQ Music is an unstable external service, yakult's current implementation independently uses the same 1,000-row ceiling, and this checkout has no sanitized evidence for accounts exceeding it. A finite bound is required before the loop can sit behind one cancellable Bridge operation.

**Impact:** An account with more than 1,000 favorited playlists cannot load the combined library, although its created-only operation remains available internally.

**Risk:** The UI may show a structural-response error for a legitimate unusually large account.

**Suggested solution:** Replace the fixed aggregate call with an evidence-backed higher bound or incremental user-library pagination that keeps cancellation and account-replacement checks exact. Never silently truncate.

**Trigger condition:** Reassess when a sanitized fixture or controlled integration returns `hasmore` after page ten, or before public alpha if large-library support becomes an acceptance requirement.

Each future item must record: ID, status, problem, why accepted, impact, risk, suggested solution, and trigger condition. Source TODOs should reference the corresponding ID where practical.
