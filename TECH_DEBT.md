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

Each future item must record: ID, status, problem, why accepted, impact, risk, suggested solution, and trigger condition. Source TODOs should reference the corresponding ID where practical.
