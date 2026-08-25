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

## TD-003 — Persisted credential is not restored at startup

**Status:** In Progress

**Problem:** `QQMusicProvider` serializes a successful credential into a versioned opaque document, the Flutter edge writes it to platform secure storage, and startup now imports and locally classifies that document. A structurally valid candidate still is not verified with QQ Music, so closing the application cannot yet regain an authenticated session.

**Why accepted:** Persistence, local import, and network verification are separate failure domains. The completed local slice proves absence, corruption, format version, invariant validation, and expiry behavior without allowing a stored key to imply server validity. The UI explicitly says server verification is still pending.

**Impact:** A user still needs to sign in again after every process restart even when the secure write succeeded; the current authenticated state is valid only for this process.

**Risk:** UI or documentation could accidentally treat a successful secure write as a restored or server-valid session.

**Suggested solution:** Verify the retained eligible candidate against QQ Music, promote it to authenticated only on explicit success, and keep credential rejection distinct from transient transport, upstream, and protocol failures.

**Trigger condition:** Must be resolved before claiming credential restore, completing M1 authentication phase, or distributing an authenticated build. Secure write and local startup import now exist, so server verification is the active next task.

## TD-004 — Secure-storage runtime behavior is not verified on every target

**Status:** Open

**Problem:** The Linux release build and integration smoke prove that the `flutter_secure_storage` federated plugin links and loads beside the Rust bridge. They do not perform a write/read/delete cycle. Android, iOS, macOS, and Windows implementations have not been built or run in this checkout.

**Why accepted:** The current finite task establishes the credential boundary without writing even fake data into the user's live keyring. Not every target runtime is available on this host, and claiming runtime verification from generated registrants would be false.

**Impact:** A platform entitlement, keyring availability, or plugin integration issue may leave the user authenticated only for the current process. The UI reports that failure without discarding the active Rust credential.

**Risk:** A build could appear to support restart restore while its platform vault is inaccessible, or test artifacts could remain in a developer keyring if future integration cleanup is incomplete.

**Suggested solution:** Add a disposable platform integration that writes unique non-account bytes, reads them back, deletes them in teardown, and verifies absence. Run it on each target before that target is accepted for authenticated distribution.

**Trigger condition:** Linux verification is required before M1 authentication acceptance. Each other target must resolve its own instance before distribution, and at least one mobile target must be verified before the M1 checkpoint.

Each future item must record: ID, status, problem, why accepted, impact, risk, suggested solution, and trigger condition. Source TODOs should reference the corresponding ID where practical.
