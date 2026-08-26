# M3 QQ Music Core Product Coverage Checkpoint — 2026-08-27

## Outcome

M3 is checkpoint-ready within its authorized QQ Music core-product scope. Twenty-one bounded slices now form coherent Search, catalog browsing, discovery, account-library, current-Track, and adaptive navigation paths without expanding Providers or introducing a second business/navigation framework.

This checkpoint does not close M1. The corrected authenticated playback → queue → synchronized word-timed lyric observation still requires user operation, and no offline or anonymous result is promoted into that acceptance evidence.

## Exit-criteria evidence

1. Track, Artist, Album, and Playlist Search preserve independent query/result/pagination state and route provider-neutral results into existing detail and queue paths.
2. Album Tracks/details and Artist Tracks/Albums form retained, reversible navigation from Search, playlist Track context, Album credits, favorite collections, and the current queue Track. Provider-specific identity parsing remains inside `provider-qqmusic`.
3. Discover exposes evidence-backed recommended playlists, current rankings, authenticated Radar Tracks, regional new Albums, and typed new-song channels. Each remains a bounded typed surface instead of a heterogeneous raw Home feed.
4. Authenticated library coverage includes combined owned/favorite playlists plus paged favorite Albums and Artists with exact credential-candidate, rejection, replacement, cancellation, and serialized-vault cleanup behavior.
5. The existing Rust positional queue and foreground playback owner serve every added Track surface. Current Track catalog navigation and the adaptive immersive artwork/lyrics page add no second transport, timer, or queue.
6. Compact and desktop flows retain state across local return, keep primary actions reachable through touch/pointer and keyboard where applicable, expose bounded semantics, and avoid the reproduced 360 px authenticated-toolbar overflow.
7. Current protocol additions have independent current-source, sanitized fixture, or bounded anonymous evidence plus offline client/Provider/Bridge/controller/widget regressions. QQ operations remain direct and live gates stay separate.
8. The baseline passes 267 offline Rust tests, strict all-target/all-feature Clippy, strict Dart formatting/analysis, 287 Flutter tests, Linux x64 Release, and packaged Linux Bridge integration. Four live QQ/WeChat tests remain gated and ignored.

## Architecture and scope review

- Static boundary scans found no handwritten Dart QQ operation names, opaque-ID parsing, QRC cipher/parser, or Rust Widget/Material dependencies.
- QQ protocol, credential semantics, opaque identity, Track mapping, pagination, and long-lived queue rules remain in Rust. Flutter owns widgets, adaptive layout, local retained navigation, focus, animation, and short-lived controller state.
- The Bridge remains typed, coarse, cancellable, and provider-neutral. Public changes were regenerated with `flutter_rust_bridge_codegen` 2.13.0; generated files are tracked and no orphan binding was found.
- Only the QQ Music Provider exists. No localhost sidecar, third-party runtime API server, download system, comments/MV/social feature, plugin runtime, background-playback architecture, cache layer, or speculative Provider abstraction was added.
- Source scans found no new TODO/FIXME/HACK marker and Git tracks no APK, AAB, build/target output, keystore, or signing artifact.

## Deferred directions

- **Track availability and quality:** deferred until sanitized unavailable, region, entitlement, or alternate-quality behavior exists. The current evidence cannot safely define Domain states.
- **“Guess you like”:** technically evidenced but product-deferred because it overlaps the existing Radar Track surface and one implementation manufactures a larger list from repeated cursorless calls. A distinct user role is required before adding it.
- **Heterogeneous Home Feed:** deferred because current shelves contain dynamic heterogeneous/tracking-rich cards and do not yet justify a stable project Domain or broad adapter.
- **Offline/cache behavior:** evidence-gated; no reproduced reliability gap currently justifies a cache policy or storage layer.
- **Local/fallback Provider:** remains later direction and requires demonstrated value plus Roadmap authorization; M3 did not broaden the product into an aggregator.

## Technical debt and Human Decisions

- **TD-001 — Open:** current Linux and Linux-host Android system-Cargo paths remain bounded and passing; FRB regeneration did not overwrite them, so no new trigger fired.
- **TD-002 — Triggered, locally blocked by HD-001:** development identity/signing remains unsuitable for distribution. No artifact was published and the checkpoint does not broaden release authority.
- **TD-003 — Resolved:** no M3 credential path weakened server-verified restore or exact account replacement.
- **TD-004 — In Progress:** Linux and Android x64 vault instances remain proven; Apple/Windows environments are still unavailable and cannot be inferred.
- **TD-005 — Open:** no sanitized account evidence reached the 1,000 favorite-playlist ceiling.
- **HD-001 — Pending, locally scoped:** it blocks final identity/signing/distribution only; it did not block this checkpoint.

No new debt or Human Decision was found.

## Validation boundaries

Offline and local platform validation proves reusable rules, static boundaries, generated Bridge packaging, and current Linux builds. It does not prove live favorite Artists/Albums, Radar personalization, recommendation quality, new-song/new-Album/Album-detail compatibility, QQ CDN playback, remote seek, physical Android behavior, Apple/Windows runtime, release signing, or M1 end-to-end acceptance.

No stored credential, account endpoint, remote QQ media, live-test gate, or user-derived fixture was used for this review.

## Post-checkpoint scheduling

No remaining unblocked task currently has stronger evidence than the deferred directions above. The repository therefore enters `NO_LEGITIMATE_WORK` while keeping `state: ACTIVE` and `global_stop: false`: new user-reported behavior, sanitized protocol evidence, an available target environment, a triggered debt condition, or the existing user-operated M1 observation can immediately produce the next bounded task. This is not project completion and does not authorize invented work.
