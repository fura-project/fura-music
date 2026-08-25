# Project Memory

- The repository started from a single MIT `LICENSE` commit (`f439866`) on 2026-08-25; no legacy architecture or implementation needs preservation.
- The product contract is QQ Music-first. Additional providers are for proven fallback or local-library needs, not breadth marketing.
- Divide Flutter and Rust by lifecycle: reusable product/domain behavior belongs in Rust; presentation-driven state belongs in Dart.
- Normal runtime communication is an in-process typed bridge. Do not introduce a localhost API sidecar.
- External QQ Music behavior must be isolated behind `QQMusicClient`; project domain models must not become aliases for raw response models.
- Never commit cookies, credentials, tokens, QIMEI identifiers, or user-derived fixtures.
- On the 2026-08-25 local Flutter 3.47.1 user-branch SDK, `flutter analyze` truncates its LSP initialization JSON when this checkout is under a path containing Chinese characters and exits 255. `dart analyze` completes normally and is the local static-analysis command until the SDK issue changes; this does not waive Flutter tests or builds.
- `flutter_rust_bridge_codegen generate` 2.13.0 does not delete generated Dart files when a Rust API module is renamed; search `apps/flutter/lib/src/rust/api` for orphaned files after generation.
