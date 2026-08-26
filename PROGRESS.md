---
execution:
  mode: CONTINUOUS_AUTONOMOUS
  state: ACTIVE
  global_stop: false
  acceptance_milestone: M1
  active_workstream: M3
  current_task: null
  next_action: DISCOVERY_PASS
---

# Current Milestone

M1's real-account playback observation remains open; M2 is checkpointed and M3 QQ Music core-product coverage is active.

# Completed Recently

- Established the current repository governance, Flutter/Rust workspaces, project Domain and Provider boundaries, generated in-process typed bridge, direct QQ Music client seam, offline test layers, and Linux packaging/integration path. No runtime API sidecar or additional Provider exists.
- Implemented the evidence-backed WeChat QR flow, Rust-owned credential semantics, server-verified restore, and serialized platform-vault access with exact cancellation and stale-result protection. The user reported successful authorized sign-in and full-process restore on Linux without sharing account material; disposable non-account vault checks pass on Linux and Android x64.
- Implemented combined owned/favorite user playlists and ordinary, liked-songs, and favorite-playlist details behind provider-scoped opaque identities. Provider pagination, mapping, cancellation, credential replacement, failure categories, and the thin Bridge have offline regression coverage; the user reported successful real-account library/detail navigation.
- Implemented QQ media dispatch/vkey resolution and corrected the evidenced false-unavailable mapping by requesting vkey `songtype: [0]` while retaining file-media identity only for the filename. Offline and bounded anonymous evidence pass, but one user-operated authenticated playback retest is still required before making a playable-source acceptance claim.
- Implemented a disposable foreground audio engine, resolution coordinator, Rust-owned positional queue semantics, adaptive queue/transport presentation, synchronized QQ lyric/QRC mapping, playback-position following, word progress, and exact line-time seeking. Local Linux file/loopback playback is proven; the real QQ playback/queue/lyric chain remains the M1 observation blocker.
- Built and inspected Linux release plus single-ABI Android ARM64/x64 artifacts. Packaged FFI, randomized vault lifecycle, local audio, and the signed-out app entrypoint pass on Android 16 x64; the ARM64 artifact starts under x64-AVD translation. This is not physical-device, QQ CDN, audio-focus, or Apple/Windows evidence.
- Added bounded M2 daily-use behavior around shared keyboard/media transport, truthful seek and volume, Track/queue actions, destructive confirmations, session-local refresh snapshots, explicit sign-out recovery, lyric following, and adaptive navigation. Repeated play/pause activation now serializes each intent against the latest transport stage and drops queued intent after track replacement. These additions reuse existing controllers and Rust queue rules rather than adding navigation, cache, background-playback, or state-management frameworks.
- Made continuous autonomous execution explicit: task, commit, review, checkpoint, milestone, report, and green-test completion all return to global task selection while `global_stop` remains false. Human Decisions remain locally scoped, and the dated M1 readiness review points to current execution and scheduling authorities without rewriting its evidence.
- Refreshed the current Android 16 x64 signed-out runtime after the recent M2 presentation changes. A direct logical-root Flutter invocation produced an x64-only Debug APK containing Flutter, Dart JNI, and Rust; clean install plus force-stop/relaunch both rendered the 1080×2400 sign-in surface without visible clipping, Flutter fatal errors, exceptions, or ANRs. The empty secure-storage algorithm migration ran only on first launch. The exact test package was uninstalled and the AVD stopped; no QR, account, QQ endpoint, or remote media was touched.
- Completed the M2 reliability and daily-use checkpoint against all eight Roadmap exit criteria. The current Linux release bundle builds; the review preserves the exact Android, physical-device, live QQ, and unavailable-platform evidence limits instead of promoting them into broader claims.
- Implemented the first M3 slice: anonymous, direct QQ Music Track search through `QQMusicClient` → `TrackSearchProvider` → provider-neutral Domain → cancellable typed Bridge → adaptive Flutter search. Query replacement suppresses stale results; first-page, empty, retry, pagination, append failure, clear, and disposal are explicit; results start or append to the existing Rust-backed playback queue. Other result types, suggestions/history, quality selection, and navigation-framework changes remain out of scope.
- Implemented the second M3 slice: Track-search items retain an optional opaque Album identity, and a direct bounded QQ Music Album-song request maps paged Tracks through the provider-neutral Catalog contract and a cancellable typed Bridge. Flutter owns explicit page/retry/append/cancel/stale/disposal state, preserves Search while Album is open, and reuses the existing Rust-backed queue without treating Album as a playlist or adding a navigation framework.
- Implemented the third M3 slice: Track-search items retain every validated credited Artist identity, including collaborations, and a direct bounded QQ Music Artist-song request maps offset-paged Tracks through the provider-neutral Catalog contract and a cancellable typed Bridge. Flutter presents explicit multi-Artist selection, owns retry/pagination/cancel/stale/disposal state, preserves Search on return, and reuses the existing queue without adding Artist detail metadata or a navigation framework.
- Implemented the fourth M3 slice: a direct anonymous QQ recommended-playlist operation maps bounded offset pages through a small provider-neutral Recommendations contract and cancellable Bridge. Adaptive Flutter discovery owns initial/empty/error/retry/pagination/append-failure/cancel/stale/disposal state, preserves its page while existing authenticated playlist detail is open, and reuses the existing queue. Raw page length—not the observed `FromLimit` feed bound—advances pagination; heterogeneous Home cards, personalization, radio/rankings, mutation, and a generic recommendation runtime remain excluded.
- Implemented the fifth M3 slice: direct anonymous Artist-Album loading maps exact-size offset pages into existing provider-neutral `AlbumSummary` values through a small Catalog contract and cancellable Bridge. The real service proved `num` is the page-size field while the conflicting `number` reference was ignored. Flutter loads Albums lazily inside the existing Artist page, preserves both sections, adapts list/grid presentation, and nests the existing Album/queue path so back returns Album → Artist → Search without reloading prior state.
- Implemented the sixth M3 slice: a separate direct anonymous Artist Search operation maps exact Desktop type-1 pages into existing provider-neutral `ArtistSummary` values through a cancellable typed Bridge. Flutter preserves independent Tracks/Artists query, results, pagination, cancellation, and stale-result state; direct results open the existing Artist Tracks/Albums and nested Album/queue path without reloading Search. Mixed Search, other result types, suggestions/history/hot words, Artist biography/follow, and a generic Search runtime remain excluded.
- Implemented the seventh M3 slice: a separate direct anonymous Album Search operation maps exact Desktop type-2 pages into existing provider-neutral `AlbumSummary` values through a cancellable typed Bridge. Flutter preserves independent Tracks/Artists/Albums query, results, pagination, cancellation, and stale-result state; direct Albums open the existing Album Track/queue path without reloading Search, and the three-type control has a 360px regression. Mixed Search, other result types, suggestions/history/hot words, Album metadata/mutation, and a generic Search runtime remain excluded.
- Revalidated the resulting baseline: Rust formatting, 203 offline Rust tests, strict Clippy, strict Dart formatting/analysis, all 216 Flutter tests, the Linux x64 Release bundle, and the packaged typed-Bridge integration pass. Four live QQ/WeChat tests remain separately gated and ignored; these results do not prove live Album Search/application compatibility, authenticated downstream playback, or search/discovery-to-CDN playback.

# In Progress

- M1's corrected authenticated playback path still needs one user-operated observation, but that is a local acceptance-evidence blocker rather than a global development stop.
- M3 remains active. Direct Album Search is implemented and verified offline through the existing Album/queue navigation. The next work item must come from a fresh bounded ranking of Roadmap-authorized gaps or reproduced problems; completion of this slice is not a stop condition.

# Next Candidates

1. Run the next bounded M3 discovery/ranking pass. QQ ranking lists remain the strongest documented catalog candidate, but are not selected until list/detail/period semantics and a finite product route are evidenced.
2. When convenient, rebuild/relaunch Linux debug and retest one ordinary track. If it plays, exercise queue navigation and synchronized word-timed lyrics; if it still fails, retain only the coarse UI state and stop speculative protocol changes.
3. Validate Apple/Windows vault/runtime paths and a physical Android device only when those target environments become available; do not infer them from the current host or emulator.

# Blockers

- User-only real-account observation remains for the corrected QQ media source, queue, and synchronized lyrics. Sign-in, process-restart restore, library, and detail are now demonstrated, but M1 remains unverified end to end until the playback fix is exercised. This blocks only the affected acceptance claim, not independent daily-use work.

# Pending Human Decisions

- HD-001: final product/display name, platform application identifiers, and signing-key ownership/custody are required before external distribution. This does not block development-signed builds, M1 acceptance testing, or independent M3 work.

# Risks

- QQ Music endpoints and authentication behavior are external and unstable; protocol work needs evidence and sanitized fixtures.
- Credential handling can create account and privacy risk; real-account probes and user-derived fixtures require deliberate, secret-safe execution.
- Startup server verification has now accepted the authorized real account after a full process restart; no credential value or response was retained.
- Linux and Android x64 runtime write/read/delete are verified with cleanup; Apple and Windows paths remain unbuilt and runtime-unverified here (TD-004).
- Successful credential exchange now has user-reported real-account acceptance evidence, but no secret-bearing trace or independently retained response exists by design.
- The successful login shape supplied the encrypted identity needed for the combined library. Other future login shapes must still fail truthfully if QQ omits it rather than silently showing a partial collection.
- Authenticated playlist/detail navigation has user-reported acceptance evidence, but no user-derived response or identifier is retained.
- Track-search request shape has two current independent implementation references plus one bounded anonymous coarse probe; the full response and Track content were not retained, and no authenticated search-to-playback observation has been claimed.
- Album-song request shape has current implementation evidence, one bounded anonymous coarse probe, and offline regression coverage. Live Album compatibility is not claimed.
- Artist-song behavior has two current independent implementation references, two bounded anonymous pagination probes, and offline end-to-end mapping/navigation coverage. The selected numeric-ID request honored the requested five-row page; no live product compatibility is claimed until the project implementation is separately exercised. The previously failing detail operation remains outside the songs-only slice.
- Recommended-playlist behavior has two current independent implementation references, bounded anonymous exact-size/pagination probes, and offline client-to-presentation regression coverage. The nested playlist shape and raw-row offset behavior were observed without retaining content; live application compatibility is not yet claimed.
- Artist-Album behavior has two current independent implementation references, bounded anonymous parameter/exact-size/pagination probes, and offline client-to-presentation regression coverage. Real service behavior selected `num` over the conflicting ignored `number` field; no Artist/Album content or identity was retained, and live application compatibility is not yet claimed.
- Artist-search behavior has three current implementation/fixture references plus one bounded anonymous exact-size/terminal-page probe. The real response supplied the numeric ID, MID, and name required by existing Artist browsing without retaining query or result content; live application compatibility is not yet claimed.
- Album-search behavior has two current independent implementation references plus one bounded anonymous five-page exact-size/terminal probe. The real response supplied the numeric ID, MID, and title required by existing Album browsing without retaining query or result content; live application compatibility is not yet claimed.
- The playback protocol correction has strong anonymous and offline regression evidence but is not yet an authenticated playable-source claim.
- Unavailable, region-filtered, or otherwise greyed QQ song rows do not yet have sanitized evidence; their long-term Domain/playback representation must not be guessed during the happy-path detail mapping.
- Current CDN dispatch returned only cleartext HTTP bases in a bounded no-account probe. Mobile playback must not globally enable cleartext traffic or silently rewrite QQ URLs before narrow platform evidence exists.
- `audioplayers` local MP3 lifecycle is proven on Linux and the Android x64 emulator. Android remote transport, audio focus/interruption, physical-device behavior, and Apple/Windows runtime paths remain unverified before release claims.
- Linux loopback HTTP seek is verified against a project byte-range fixture; actual QQ CDN seek remains part of the pending authenticated playback observation and is not implied by that local result.
- The corrected ARM64 application starts under the current x64 AVD's ARM64 translation layer, but this is not physical-device evidence and does not prove hardware-specific rendering, media, or lifecycle behavior.
- A local credential timestamp cannot prove server validity; transport failures must not be mapped to signed-out or rejected state.
- A generated bridge can grow into a second business layer unless its public surface stays coarse and typed.
- The Provider rejects a favorite collection that still has more data after 1,000 rows rather than looping without bound or silently truncating it (TD-005).
- Cargokit 2.13.0 assumes rustup; Linux x64 and Linux-host Android ARM64/x64 use narrow direct system-Cargo paths tracked as TD-001, while other bridge targets remain unverified.
- Release identity and signing defaults have reached their packaging trigger (TD-002). HD-001 must be decided before external distribution; current artifacts remain development-only.
- Local sign-out ordering and failure presentation are regression-tested, but the actual account credential key has deliberately not been deleted by automation; user-operated sign-out remains separate manual acceptance evidence.
