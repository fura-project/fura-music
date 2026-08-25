# ADR 0001 — In-process Flutter and Rust architecture

- **Status:** Accepted
- **Date:** 2026-08-25

## Context

The product needs a modern cross-platform UI and reusable long-lived music behavior. A local API server would add deployment, lifecycle, security, serialization, and failure complexity without providing a current user benefit.

## Decision

Use Flutter for presentation and short-lived UI state, and a Rust core for reusable domain, provider, protocol, resolution, lyric, storage-policy, and download behavior. Both run in the same application process and communicate through a thin typed FFI bridge.

Module placement follows lifecycle: logic that should survive replacing Flutter belongs in Rust; logic that primarily exists to present Flutter UI remains in Dart.

## Alternatives

- Flutter-only implementation.
- Flutter communicating with a localhost Node, Python, or Rust service.
- Rust controlling application presentation state.

## Why

This boundary keeps QQ Music and music-domain behavior reusable without turning Rust into a remote UI state machine. In-process calls also remove a needless runtime service dependency.

## Consequences

- Bridge types and ownership require deliberate design and tests.
- Raw provider protocol models cannot cross directly into Flutter.
- UI-only state must not be mirrored through FFI.
- No runtime sidecar may be introduced without a superseding accepted ADR.
