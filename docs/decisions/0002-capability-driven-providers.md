# ADR 0002 — Capability-driven, UI-free providers

- **Status:** Accepted
- **Date:** 2026-08-25

## Context

Music services expose different features and semantics. Treating every provider as a complete interchangeable platform either leaks provider detail everywhere or creates false abstractions. The product is explicitly QQ Music-first.

## Decision

Providers expose domain data through explicit, small capabilities such as authentication, catalog, user library, lyrics, and media resolution. They never construct Flutter UI. `QQMusicClient` owns raw QQ Music protocol behavior; `QQMusicProvider` maps it into stable project domain models.

The first phase supports architecture-level composition only. It does not create a dynamic plugin runtime or marketplace.

## Alternatives

- A single universal provider interface requiring every feature.
- Provider-supplied widgets or pages.
- An arbitrary-code plugin marketplace from the first release.

## Why

Capabilities preserve real differences while keeping Flutter responsible for one coherent QQ Music product experience. Deferring runtime plugins avoids speculative infrastructure.

## Consequences

- Feature availability must be explicit at provider and presentation boundaries.
- Shared abstractions should appear only after real common behavior exists.
- Adding another provider is a product decision, not merely an implementation task.
