# M5.6 Product-Completeness Audit

**Status:** Completed — the one authorized Track-context inconsistency is resolved; no further material M5 implementation gap is established before M5.7 review.

## Scope and authority

This audit compares the implemented authenticated product, current automated/platform evidence, `PROJECT.md`, accepted Human Decisions, M5 exit criteria, technical debt, and explicit non-goals. It does not treat mainstream competitors as requirements, call QQ Music, access stored credentials, invent release claims, or reopen deferred features merely to keep development active.

Every material remaining first-release gap is assigned to exactly one class below. Historical compatibility risks for each individual QQ endpoint remain in `PROGRESS.md`; they are consolidated here where they imply the same next authority or evidence action.

## Implemented product baseline

- Home is the authenticated default and truthfully routes to distinct retained Discover, Search, and Library destinations. It is intentionally a small starting surface, not an unimplemented heterogeneous feed.
- Library exposes retained Playlists, favorite Albums, and favorite Artists. Search covers Tracks, Artists, Albums, and Playlists. Discover covers recommended Playlists, rankings, Radar, New Albums, and New Songs.
- One Rust positional Queue owns sequential/shuffle and repeat off/all/one. One Flutter foreground-music owner feeds the mini and expanded Now Playing, Queue, synchronized lyrics, word timing, seek, volume, and transport surfaces.
- Playlist/Search/current-Track context can reach validated Album and Artist destinations. Expanded Now Playing also exposes read-only comments and one exact Track-associated MV without creating social or video-platform roots.
- The official-Flutter Material desktop/compact baseline, retained navigation, 360 px reachability, keyboard/pointer/touch paths, coarse failure states, cancellation, and stale-result suppression have broad offline regressions.

The current Home is therefore not classified as a gap merely because other streaming products use personalized feeds. It meets the accepted small-and-truthful M5 role with no unsupported personalization or duplicate Discover responsibility.

## 1. Agent-authorized

### A-1 — Shared Track rows expose already-validated Album/Artist context (Resolved)

**Evidence:** Playlist detail and Search Track rows expose their validated Album and credited-Artist context, and current Track context is globally reachable. The shared `MusicTrackTile` used by Album Tracks, Artist Tracks, rankings, Radar, and New Songs receives the same provider-neutral `PlaylistTrackSummary`, including optional Album and credited Artists, but exposes only play and add-to-Queue. Existing retained routing callbacks can open those destinations without protocol, Domain, Queue, state-management, or navigation changes.

**User value:** A Track behaves predictably across the core catalog: users can browse its known Album or credited Artists from any dense Track surface instead of first playing it or repeating a Search.

**Authority:** HD-003 explicitly authorizes a bounded Track-context audit, and M5 exit criteria 2, 7, 8, and 9 permit this presentation completion while forbidding broader infrastructure.

**Implemented finite scope:** One optional, labeled Material context menu now appears on the shared Track tile only when validated context and a usable retained-route callback exist. Tap-to-play and the direct Queue action are unchanged. Album pages expose credited Artists; Artist pages expose Albums; ranking, Radar, and New Song surfaces expose both through the existing topmost retained context routes. Missing context remains absent, collaborations remain explicit choices, and return restores the exact originating page.

**Acceptance criteria:**

1. The shared tile omits the menu when no usable context exists and never parses opaque identity.
2. One Album and every credited Artist are represented without inventing labels or destinations.
3. Existing play/Queue keys and callbacks remain unchanged.
4. A 360 px regression proves the additional affordance does not overflow or hide play/Queue behavior.
5. Keyboard/tap menu activation and exact callback selection have focused tests; at least one retained Discover path proves context return does not reload or replace playback ownership.
6. Strict Dart/Flutter and relevant repository baselines pass.

**Major risks:** Trailing-action crowding at compact widths, duplicate actions inside Album/Artist context, callback propagation crossing the wrong retained origin, and accidentally making absent context look authoritative.

**Explicit non-goals:** Play-next, Queue insertion/reorder, Track details pages, MV/comment row actions, favorite/playlist mutation, new protocol fields, new navigation/state framework, or exposing context from raw QQ data.

**Resolution evidence:** Focused shared-tile tests prove 360 px reachability, menu omission without usable context, exact Album selection, exact multi-Artist selection, and unchanged play/Queue callbacks. The retained Radar regression proves Radar → Album → Radar returns without reloading Radar or replacing queue behavior. `dart analyze`, all 336 Flutter tests, `git diff --check`, and Linux x64 Release build pass. Rust, Bridge, dependencies, protocol, Domain, Queue, and navigation ownership were unchanged, so no live QQ or credential access was performed.

### A-2 — M5 checkpoint review

With A-1 resolved and this audit finalized, M5.7 is the next authorized governance/review task. It may close the milestone only against the existing exit criteria and evidence boundaries; it may not convert pending live, platform, release, or out-of-scope work into passing claims.

## 2. Evidence-blocked

- **M1 live playback chain:** corrected authenticated media resolution → foreground playback → Queue navigation → synchronized/word-timed lyrics still needs one coarse user-operated observation. Offline/local playback cannot replace it.
- **Live comments and MV behavior:** current independent protocol references and offline client-to-presentation coverage exist, but this repository has not called those QQ operations. A future bounded, secret-safe observation can establish compatibility; repeated speculative endpoint changes are not authorized.
- **Evidence-gated offline/cache/fallback direction:** the later Roadmap permits evaluation only after demonstrated daily-use value and failure evidence. No current measurement shows that a cache or another Provider is the highest-value first-release task.

## 3. Environment-blocked

- iOS, macOS, and Windows build/runtime behavior is unavailable on this Linux host. Their secure storage, native video, playback, packaging, focus, and adaptive behavior remain unverified.
- Android x64 packaging and bounded emulator evidence exist, but physical-device audio focus, hardware video decode, background/interrupt behavior, and real QQ sources are not established. ARM64 packaging under translation is not physical ARM64 evidence.
- Broad all-platform visual approval cannot be inferred from Linux/widget coverage.

These are target-specific evidence gaps, not permission to emulate unavailable platforms or weaken current claims.

## 4. Human-decision work

- HD-001 controls final name, application identifiers, signing custody, and external distribution. TD-002 and the release-time native-media notice work in TD-006 remain locally blocked with it.
- Any decision to require background playback as a release criterion, add remote mutation, or promote a new Provider would expand the accepted M5 product boundary and needs new human product authority rather than an autonomous implementation assumption.

## 5. Out of scope

- A dynamic heterogeneous or duplicated Discover-style Home feed; search history, hot words, suggestions, or mixed Search without separate evidence/authorization.
- Comment posting/liking/replies, follow/favorite/playlist mutation, social profiles, and community systems.
- MV Search/Discover, related-video galleries, HLS/quality UI, fullscreen/PiP, video downloads/cache, and a generic video platform.
- Background-playback architecture, persistent recent-history semantics, download management, additional/local/fallback Providers, aggregation, podcasts, and a plugin runtime.
- Quiet/Focus/Luminous/Temporal personas, signature visual experiments, and speculative theme infrastructure.

These may be reasonable future ideas, but they are not incomplete M5 implementation.

## Current conclusion

A-1 was the only material, evidenced implementation gap found inside existing M5 authority and is now resolved using data and retained routes already present. Re-review of the diff, tests, architecture boundary, scope, debt triggers, and evidence classes found no additional authorized code task. M5.7 checkpoint review is therefore next; evidence-blocked, environment-blocked, human-decision, and out-of-scope items remain open in exactly those classes rather than being promoted into autonomous implementation work.
