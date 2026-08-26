# Roadmap

## Current Milestone — M1 First QQ Music Vertical Slice

### Goal

Deliver the smallest coherent user journey from QQ Music sign-in through word-level lyrics while proving the in-process Flutter/Rust architecture.

### Progressive phases

1. **Executable foundation** — governance, Flutter/Rust workspaces, thin typed bridge, minimum domain/provider boundaries, QQ Music client seam, and offline tests.
2. **Authentication** — login flow, credential state, safe persistence boundary, and restore behavior.
3. **User library** — user playlists and playlist details backed by real QQ Music behavior and sanitized fixtures or repeatable integration evidence.
4. **Playback** — media resolution, playback, and queue behavior.
5. **Lyrics** — lyric loading, QRC parsing, and basic word-level presentation.

### Acceptance criteria

- A user can complete sign-in, restart the app, and regain the appropriate credential state.
- The user can browse their playlists, open one, start a playable track, and manage the queue.
- Synchronized lyrics and a basic word-level lyric experience work for supported tracks.
- Flutter and Rust remain in one process with a thin typed boundary.
- QQ Music protocol and mapping behavior has offline regression coverage; live integration tests are separate.
- Linux desktop and at least one mobile target build successfully before the milestone checkpoint.
- No runtime third-party QQ Music API server or unapproved provider expansion exists.

### Dependencies

- Verified QQ Music protocol behavior from real responses, repeatable integration tests, or cross-validation across independent active implementations.
- A platform-safe credential storage approach before any public alpha.

## Completed Checkpoint — M2 Reliability and Daily-Use Quality

### Goal

Make the implemented M1 chain reliable and coherent enough for daily use without expanding the product beyond QQ Music-first playback and library flows.

### Authorized themes

- Failure recovery and truthful unavailable/error states.
- Playback, queue, lyric, and authentication resilience.
- Adaptive desktop/mobile interaction quality and accessibility.
- Packaging and runtime evidence for already intended platforms.
- Cache policy only when a demonstrated reliability or daily-use gap requires it.
- Bounded product-completeness, UX-flow, and architecture-boundary discovery inside these themes.

Task selection may start from existing evidence or a bounded discovery pass. A remaining M1 acceptance observation does not globally block independent M2 work and does not become implicitly satisfied by it. This workstream does not authorize new Providers, Search, Comments, MV, Downloads, Social features, plugin infrastructure, or unrelated product expansion.

### Progress

Completed slices cover shared keyboard/media transport, truthful seek and volume, adaptive Track and queue actions, destructive confirmations, ordered local sign-out recovery, meaningful accessibility announcements, album-art queue presentation, synchronized lyric following/seeking, session-local library/detail refresh snapshots, local detail back behavior, collection-position restoration, and originating-row focus restoration. These changes reuse the existing controllers and Rust queue rules rather than introducing new navigation, cache, background-playback, or state-management systems.

### Exit criteria

1. The implemented sign-in, restore, library, detail, playback, queue, and lyric chain has explicit loading, empty, failure, retry, and cancellation behavior where applicable.
2. Playback and queue controls remain coherent under repeated user actions, unavailable media, resolution failures, and stale asynchronous completion.
3. Library/detail refresh and navigation preserve or clear visible state intentionally rather than through accidental rebuild behavior.
4. Desktop and compact layouts keep their primary actions reachable with keyboard, pointer, and touch where applicable.
5. Meaningful authentication, library, playback, queue, and lyric changes expose non-duplicated accessibility semantics.
6. Offline Rust and Flutter suites cover the reusable rules and reproduced regressions; live QQ behavior remains separately gated.
7. Linux and the available Android development targets retain bounded build/runtime evidence, with unsupported claims recorded explicitly.
8. A checkpoint review finds no known high-value M2 correctness or daily-use gap left unaddressed or untracked, and M1 user-operated evidence remains represented truthfully.

### Checkpoint

Completed on 2026-08-26. The criterion-by-criterion evidence and its explicit platform/live-service limits are recorded in `docs/development/m2-checkpoint-review.md`. Later M2-class regressions remain valid bug work; the checkpoint is not a prohibition on fixes.

## Active Workstream — M3 QQ Music Core Product Coverage

### Goal

Expand from the first vertical slice into a coherent QQ Music client while preserving the accepted Provider, Domain, Bridge, and presentation boundaries.

### Authorized direction

- QQ Music catalog Search.
- Evidence-backed QQ Music home and recommendation surfaces.
- Album and Artist browsing.
- Richer QQ Music library navigation.
- Track availability and quality representation where protocol evidence exists.
- Other QQ-native catalog flows discovered from real product use and bounded before implementation.

M3 begins with bounded discovery after the M2 checkpoint. Each slice requires discovery or protocol/product evidence, a finite acceptance boundary, and offline regression coverage where reusable mapping or rules are introduced. This is not authorization for external Providers, podcast/social features, a plugin marketplace, or a download platform.

### Progress

- **Track search:** implemented as the first finite M3 slice on 2026-08-26. Direct anonymous QQ Music protocol mapping returns provider-neutral paged Tracks through a cancellable typed Bridge. The adaptive Flutter surface owns query replacement, empty/error/retry/pagination state and hands results to the existing queue/playback path. Offline protocol, Provider, Bridge, controller, navigation, and primary UI-flow tests pass; this is not a real-account CDN playback claim.
- **Album browsing:** selected as the next finite slice after current implementation evidence and a bounded anonymous Album detail/song probe. Its boundary is Search-result Album identity → paged Album Tracks → existing queue, not full Album metadata, mutation, Artist browsing, multi-type Search, or a broad catalog abstraction.

## Later direction

After coherent QQ Music core coverage, evaluate deeper platform integration and evidence-backed offline/cache behavior. Narrow local-library or media-fallback capabilities come later and require demonstrated user value; they must not turn the product into a multi-source aggregator.
