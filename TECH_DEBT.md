# Technical Debt

Technical debt is reviewed after each finite task. States are `Open`, `Triggered`, `Scheduled`, `In Progress`, `Resolved`, and `Accepted Permanently`.

## TD-001 — Linux bridge build bypasses Cargokit

**Status:** Open

**Problem:** `flutter_rust_bridge` 2.13.0 generates a Cargokit backend that invokes `rustup` unconditionally. The Arch development environment intentionally uses supported system `rustc` and `cargo` packages, where installing rustup would conflict with the system toolchain. Linux therefore has a small direct-Cargo CMake integration while other platforms retain generated Cargokit integration.

**Why accepted:** Linux is first-class and the direct build uses the same Cargo workspace, lockfile, crate type, and Rust compiler already validated by the core suite. Replacing the whole bridge or installing a conflicting toolchain would be larger and riskier during the executable-foundation task.

**Impact:** Linux's `rust_builder/CMakeLists.txt` is no longer fully generator-owned.

**Risk:** Re-running bridge integration could overwrite the customization; other targets still need their own verified toolchain path.

**Suggested solution:** Adopt upstream Cargokit/native-assets system-Rust support when available, or move the minimal direct build into a shared project-owned integration once a second platform proves the required common behavior.

**Trigger condition:** Reassess when bridge integration is regenerated, upstream adds system-Rust support, or M1 reaches its first mobile build task.

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

Each future item must record: ID, status, problem, why accepted, impact, risk, suggested solution, and trigger condition. Source TODOs should reference the corresponding ID where practical.
