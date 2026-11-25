# Collection Loading, Search & Identity Convergence Audit (2026-11-25)

## 1. Baseline & Protected Governance

- **Repository baseline:** `43ed5b2a6bc7b2b8ac93b2884897dcd61f498648`
- **Protected decisions:** HD-032 (upstream integrity & local omission), HD-035 (Provider continuation, single-request ownership, viewport demand, comments, Queue continuation, Roam), HD-036 (protocol evidence & license boundary), HD-037 (MediaKit sole engine & platform media session ownership).
- **New decision:** **HD-038** in `HUMAN_DECISIONS.md` (superseding only HD-035's old 2-page / 20-match local search cutoff for Liked Songs and Recent Plays).
- **Scope discipline:** No new dependencies, no SQLite/FTS/Tantivy, no generic `CollectionManager`, no second account cache, no KuGou or Direct Track Like Status production promotion, no playback-stack or Linux MPRIS changes, no FRB Bridge API signature changes, and no automated real-account access.

## 2. Confirmed Pre-Existing Production Defects & Deterministic Risks

| # | Area | Finding | Classification | Status |
|---|---|---|---|---|
| 1 | Liked Songs / Recent Plays search | `PagedTracksController.requestSearchWindow` defaulted to 2 remote pages, `LikedSongsPage` paused at `matches.length >= 20`, and `BoundedViewportPageDemand` coupled search progression to scrolling (`onRetreat` even cancelled search scans on upward scroll). Warm-cached 1,117-track Liked collections stopped at 300 tracks (`found=0`) for deep targets at index 1,050 despite all 12 pages already cached in `TrackLikePresentationController`. | Confirmed production defect | Fixed (`requestSearchCoverage`, synchronous validated cached continuation drain, decoupled from viewport scroll) |
| 2 | `TrackLikePresentationController` (7A) | `refreshSnapshot()` and mutation presentation invalidation cleared `_sharedPages` without bumping a snapshot/page revision fence, allowing delayed non-cooperative Futures from an earlier scan/refresh to mutate `_refreshIds`, `_likedTrackIds`, or `_sharedPages`, or a stale pre-refresh session/replaced failure to invoke `_invalidate(null)` and wipe the active session. | Deterministic risk reproduced | Fixed (`_pageRevision`, `_scanRevision`, `_refreshRevision` fences checked before `_isSessionFailure` + non-cooperative Future tests) |
| 3 | `TrackLikePresentationController` (7B) | `_beginSharedLoad` bypassed `_validPage`, `_validPage` omitted `isValidRawOffsetPage` + `providerId` verification, `_commitRefresh` set `_complete = true` even when `result.hasMore == true`, and `_scanRefresh` logged `outcome=success` even on aborted refreshes. | Confirmed production defect (exposed 5 legacy test fixtures with invalid `nextOffset`) | Fixed (unified `_validPage`, `presentationComplete: !result.hasMore` in `_commitRefresh`, accurate refresh outcome diagnostic) |
| 4 | `TrackLikePresentationController` & `LikedSongsPage` (7C) | Confirmed mutations without `refreshAdditionalState` (e.g., Heart unlike from Now Playing / Home / Search) left deleted tracks in `_sharedPages` and mounted `LikedSongsPage`, allowed `PagedTracksController` to mix pre-mutation page 0 with post-mutation pages 1..N, and left `_loading` stuck `true` / `_nextOffset` stale during partial scans. | Confirmed production defect | Fixed (immediate `_sharedPages` invalidation + `_loading`/partial-cursor reset, `cachedSnapshotRevision` fence in `PagedTracksController`, and active/deferred `presentationRevision` refresh in `LikedSongsPage`) |
| 5 | `TrackLikePresentationController` (7D) | Diagnostics logged `networkRequests: 1` before consulting `_sharedPages`, miscounting cache hits and pending single-flight joins as transport requests. | Confirmed diagnostic defect | Fixed (`_beginSharedLoad` logs `networkRequests: 1` only on real transport miss; `networkRequests: 0` with `cache=hit` or `single_flight_join=true` otherwise) |
| 6 | Liked Songs & Recent Plays search states | Empty-match states claimed final "No matching tracks" / "Searched all N tracks" even while `hasMore == true` (paused/idle); non-search all-omitted pages routed into search-empty copy; non-retryable `alreadyRunning` exited as `paused` instead of `interrupted`; `RecentPlaysPage.didUpdateWidget` did not cancel search scans when becoming inactive. | Confirmed production defect | Fixed (distinct searching / paused / interrupted / partial / complete / true-empty states, non-search guard, inexact-total fallback, inactive cancel) |
| 7 | `PartialResultsNotice` red warning & announcement | Used `colorScheme.tertiaryContainer` (terracotta/brick red in Magazine Editorial), and advancing `_lastAnnouncedPartialRevision` while the footer was offscreen swallowed the first search announcement. | Confirmed production defect | Fixed (calm neutral `cardSurface` + `hairline` in Editorial and `surfaceContainerHigh` in Material 3; collection-scoped search copy `collectionSearchPartialNotice`; `onAnnounced` callback guarantees single announcement when rendered and zero re-announcement on query replacement) |
| 8 | `PlaylistTrackSearchIndex` scaling | Incremental page appends re-fingerprinted the entire prefix on every page (`O(N^2)`, 5,667 ms at 50k tracks), and fuzzy matching allocated a 2D edit-distance matrix per token. | Confirmed performance bottleneck | Fixed (`collectionGeneration` O(1) append fast path, single-pass normalization, reusable 3-row `Uint8List(65)` Damerau-Levenshtein + zero-alloc edit-distance-1 fast path) |
| 9 | `RadarController` & `HomePage` Radar handoff | `_prefetchInitialPages` bypassed `_appendPump`; Discover Radar stopped at 20 / 2 follow-up pages; `collectionPlaybackSource()` lacked session sharing & cross-page dedup; `HomePage._radarSlot` eagerly built `collectionPlaybackSource` in `build()`, poisoning flat `seen` on second tap and stalling at 1 song; `operation.run()` throws stranded `isLoadingMore`; `_RadarSessionPages` retained resolved pages without bound. | Confirmed production defect | Fixed (single serial `_appendPump`, Discover target `30` / `maxInitialPrefetchPages: 3`, ref-counted `_RadarSessionPages` with 64-page resolved cap, per-page `firstSeenPage` dedup + lazy `onPlay` source creation in `HomePage`, `try/catch` around `operation.run()`) |
| 10 | `QueuePlaybackController` & Rust `PlaybackQueue` | `replaceAndPlayCollection` awaited slow first-track `playTrack(current)` before scheduling initial Radar Queue fill; `setOrder` / `setRepeatMode` cleared `_collectionSource` and blocked initial fill under Shuffle / Repeat One / Repeat All; Rust `PlaybackQueue::extend` did not preserve played shuffle prefix while mixing newly appended tracks into the unplayed tail. | Confirmed production defect | Fixed (decoupled initial fill scheduling, separated bounded initial fill from ongoing `sequential && repeat-off` continuation, preserved `_collectionSource` across mode switches, Rust `extend_shuffle_cycle` tail mixing) |
| 11 | `QqMusicProvider::recover_omitted_tracks` cancellation | Dropping an in-flight recovery future mid-await left its closed `watch::Receiver` in `in_flight` for the rest of the session generation, permanently failing subsequent retries for that track. | Deterministic concurrency defect reproduced | Fixed (`InFlightOmittedRecoveryGuard` RAII drop guard + closed-waiter cleanup in `plan_omitted_track_lookup`) |

## 3. Workstream A — Decoupled Collection Search Architecture & Benchmarks

### Architecture Separation (Inside Existing Owners)

```text
Rust Provider
    ↓
TrackLikePresentationController._sharedPages (Account-Scoped Shared Page Cache)
    ├── Authoritative Membership (_likedTrackIds, _membershipComplete)
    ├── Read-Only Validated Contiguous Snapshot (CachedPlaylistTrackPagesGateway)
    └── Paged Browse & Search Coverage (PagedTracksController -> PlaylistTrackSearchIndex)
```

- `CachedPlaylistTrackPagesGateway.readCachedContinuation` walks strictly from `fromOffset` along validated contiguous raw-offset pages (`_validPage`, advancing `nextOffset`, consistent exact totals) without exposing internal mutable maps.
- `membershipComplete` never implies `presentationComplete`.
- Ordinary browsing still renders only the virtualized list viewport (`ListView.builder`) without pre-building offscreen widgets or downloading all artwork.

### P01 — Search Index Benchmark (Same Deterministic Synthetic Fixture)

| Collection Size | Metric | BEFORE (`43ed5b2`) | AFTER | Speedup / Delta |
|---|---|---:|---:|---:|
| **1,000 tracks** | Initial build | 52 ms | 37 ms | 1.4x |
| | Incremental append (100/page) | 17 ms | 11 ms | 1.5x |
| | Full rebuild (generation change) | 16 ms | 13 ms | 1.2x |
| | Exact query (`Nevada`) | 32.3 ms | 7.2 ms | 4.5x |
| | Fuzzy query (`neveda`) | 8.6 ms | 1.7 ms | 5.1x |
| | Rapid query replacement (8 queries) | 21.0 ms | 9.1 ms | 2.3x |
| | RSS delta | +11.8 MB | +8.2 MB | -3.6 MB |
| **10,000 tracks** | Initial build | 132 ms | 124 ms | 1.1x |
| | Incremental append (100/page) | 354 ms | 105 ms | 3.4x |
| | Full rebuild | 120 ms | 83 ms | 1.4x |
| | Exact query (`Nevada`) | 23.5 ms | 12.4 ms | 1.9x |
| | Fuzzy query (`neveda`) | 17.0 ms | 11.7 ms | 1.5x |
| | Rapid query replacement (8 queries) | 120.6 ms | 73.6 ms | 1.6x |
| | RSS delta | +20.6 MB | +19.6 MB | -1.0 MB |
| **50,000 tracks** | Initial build | 563 ms | 390 ms | 1.4x |
| | Incremental append (100/page)* | **5,667 ms** | **733 ms** | **7.7x** |
| | Full rebuild | 573 ms | 354 ms | 1.6x |
| | Exact query (`Nevada`) | 99.5 ms | 40.8 ms | 2.4x |
| | Fuzzy query (`neveda`) | 97.0 ms | 39.8 ms | 2.4x |
| | Rapid query replacement (8 queries) | 498.9 ms | 234.1 ms | 2.1x |
| | RSS delta | +85.7 MB | +69.1 MB | -16.6 MB |

\* Note: The incremental benchmark harness calls `tracks.sublist(0, end)` 500 times for 50k tracks (12.5M pointer copies inside the test harness itself), identical between BEFORE and AFTER runs. At 1k–10k tracks both exact and fuzzy queries stay below the 16.6 ms 60 fps budget even in unoptimized Dart debug VM; 50k synchronous queries drop from ~99 ms to ~40 ms without introducing any external index or isolate complexity (if real accounts ever exceed 20k tracks, isolate offloading remains a clean future option).

### P02, P03, P06 — Warm vs Cold 1,117-Track Liked Collection (`Nevada` at Index 1,050)

| Scenario | Processed | Matches Found | Extra HTTP | Duplicate Pages | Peak Concurrency | Elapsed |
|---|---:|---:|---:|---:|---:|---:|
| **BEFORE** Warm cache (`requestSearchWindow`) | 300 | **0 (missed)** | 0 | 0 | 1 | paused at 300 |
| **AFTER** Warm cache (`requestSearchCoverage`) | **1,117** | **1 (`Nevada`)** | **0** | **0** | **0** | **4.9 ms** |
| **AFTER** Cold cache (`requestSearchCoverage`, 0 ms mock net) | **1,117** | **1 (`Nevada`)** | **12** (exact 12 pages) | **0** | **1** | **7.5 ms** |

## 4. Workstream B — Historical Track Identity & Exact Detail Recovery

### SongMid Failure Classification & Exact Numeric Membership Retention

In `crates/qqmusic-client/src/playlist_detail.rs`:
- Added `SongMidFailureReason` (`Missing`, `Null`, `InvalidType`, `Blank`, `TooLong`, `InvalidCharacters`) and `QqMusicOmittedTrackCandidate` (with redacted `Debug`).
- `QqMusicPlaylistTracksPage::omitted_song_mid_candidates()` exposes omitted rows that still carried valid numeric `(track_id, song_type)` so numeric membership stays authoritative (`membership_track_ids` unaffected) without inferring removal solely from a missing/invalid `SongMid`.

### External Protocol Evidence (HD-036 License Boundary)

- Inspected `L-1124/QQMusicApi` (`modules/song.py`, `models/song.py`, `modules/recommend.py`; **GPL-3.0**) and `Yyyangshenghao/simple-music` (`server/lib/qq-client.ts`; **GPL-3.0**) strictly as **behavioral/protocol evidence only — zero code copied**.
- Confirmed Fura already calls `music.pf_song_detail_svr/get_song_detail_yqq` with `song_mid` in `crates/qqmusic-client/src/music_video.rs`.
- Built clean-room `QqMusicClient::track_detail_by_id` and `recover_omitted_track_by_identity` in `crates/qqmusic-client/src/track_detail.rs` using `{"song_id": u64}` on Web public `comm` (`ct: 24, cv: 0`), requiring exact `(track_id, song_type, safe_media_mid)` agreement and stopping immediately on rate-limit codes.
- Added bounded, single-flight (`tokio::sync::watch`), session-generation-scoped `QqMusicProvider::recover_omitted_tracks` in `crates/provider-qqmusic/src/lib.rs` (`MAX_OMITTED_TRACK_RECOVERY_BUDGET = 3`, cache cap `256`).
- **Production playlist reads remain non-blocking:** `QqMusicProvider::playlist_tracks_page` does **not** automatically invoke remote detail recovery until a live gate verifies real upstream behavior on `get_song_detail_yqq` with `song_id`.

### Capability Boundary Matrix for Unrecoverable Historical Tracks

| Capability | Required QQ Identity | Behavior When Track Lacks Valid `SongMid` |
|---|---|---|
| Authoritative Heart Membership | `(track_id, song_type)` | **Supported** — retained in `membership_track_ids` (`track-membership:<id>:<type>`). |
| Visible Playlist Row / Local Search | Valid `safe_media_mid` + display fields | **Omitted** — counted in `omitted_track_count`; calm `PartialResultsNotice` shown; never forged. |
| Comments (`track_comments`) | Valid canonical track identity (`id`, `song_type`, `mid`) | **Rejected preflight** (`CommentsError::InvalidResponse`) without transport call. |
| Lyrics (`lyrics`) | Valid canonical track identity (`id`, `mid`) | **Rejected preflight** (`LyricsError::InvalidResponse`) without transport call. |
| Track Like Mutation (`set_track_liked`) | Valid numeric `(track_id, song_type)` in canonical ID | **Rejected preflight** (`LibraryMutationError::InvalidRequest`) if numeric ID absent; numeric-only ID rejected by canonical parser unless exact identity exists. |
| Media Playback (`resolve_media`) | Valid `safe_media_mid` (or `file_media_mid`) | **Rejected preflight** without transport call; never substitutes numeric ID as MID or fuzzy-matches another song. |

### Minimal Live-Gate Plans (NOT Executed Automatically)

1. **Anonymous structural live gate (2 public requests, zero account/cookie):**
   - Already implemented as `#[ignore]` test in `crates/qqmusic-client/tests/live_track_detail.rs`:
     `FURA_QQ_LIVE_TRACK_DETAIL_TEST=1 cargo test -p qqmusic-client --test live_track_detail -- --ignored`
   - Fetches 1 public `new_songs` track, then queries `get_song_detail_yqq` with `song_id` and verifies exact `(track_id, song_type, song_mid)` equality. Zero titles/identities/bodies printed.
2. **Real-account offset-400 diagnosis gate (2 authenticated requests, requires fresh explicit Human authorization):**
   - Not run in this session. If Human authorizes a fresh single-shot read-only gate: (1) fetch Liked Songs offset `400` size `100` to log ONLY the exact `SongMidFailureReason` enum variant and `(has_numeric_id, song_type)` without printing titles/IDs/cookies; (2) issue 1 `get_song_detail_yqq(song_id)` check to classify whether the historical row is recoverable (`RecoveredExact`), empty/removed (`UnrecoverableEmpty`), or mismatched (`IdentityMismatch`).

## 5. Workstream C — Radar Initial Fill, Shared Session & Queue Handoff

- **Serial single pump:** `RadarController` unifies initial prefetch, `loadMore()`, and `prefetchTo()` through `_appendPump(pump, generation)` (eliminating concurrent Page 2 races).
- **Bounded initial targets:** Discover Radar uses `initialPrefetchTarget: 30, maxInitialPrefetchPages: 3` (4 pages total: `1 + 10 + 10 + 10 -> 31`), while Home preview stays at `initialPrefetchTarget: 0` (1 page).
- **Per-refresh shared session (`_RadarSessionPages`):** Pending and resolved pages are shared between `RadarController` and detached `CollectionPlaybackSource` via ref-counted cancellation (`retain`/`release`), so rapid Play joins pending Page 2 single-flight (`dup_pages = 0`) and navigating away (`RadarController.dispose()`) never aborts active Queue replenishment.
- **Exact cross-page dedup:** Both `RadarController` and `collectionPlaybackSource()` deduplicate by `(providerId, opaqueId)`.
- **Playback mode & decoupled Queue fill:**
  - `QueuePlaybackController.replaceAndPlayCollection` schedules `_maybeDemandCollection()` **before** `await _playback.playTrack(current)`.
  - Bounded initial fill (`_collectionNeedsInitialFill`) fills to the collection's initial target (`50` for Radar) regardless of Shuffle / Repeat One / Repeat All without mutating the user's mode.
  - Ongoing low-watermark continuation (`_collectionAllowsOngoingContinuation`) remains strictly `sequential && repeat-off`.
  - `setOrder` and `setRepeatMode` preserve `_collectionSource`, clear stale terminal claims, cancel non-initial-fill lookahead when leaving `sequential && repeat-off`, and resume continuation if returning.
  - Rust `PlaybackQueue::extend` (`crates/music-domain/src/playback_queue.rs`) calls `extend_shuffle_cycle(old_len)` to preserve the played shuffle prefix `shuffle_order[0..=cursor]` while mixing newly appended indices into the unplayed tail.

### P04, P05, P06 — Radar Queue Timeline (120 ms Simulated Slow Media Resolution, 10 ms/Page)

- **Click -> Queue 20 tracks:** `33 ms` (before first-track media resolved)
- **Click -> Queue 30 tracks:** `44 ms`
- **Click -> Queue 50 tracks:** `66 ms`
- **Click -> First-track playback:** `140 ms` (bound only by 120 ms media resolve, never blocked on pages 2..6)
- **Duplicate Radar page fetches:** `0`; **Peak Radar concurrency:** `1`.

## 6. Deterministic Verification Matrix (S01–S10, I01–I06, R01–R10, P01–P06)

- **S01–S10 + 7A–7D + Section 13 + Damerau-Levenshtein equivalence:** `apps/flutter/test/library/collection_search_convergence_test.dart`
- **I01–I06:** `crates/qqmusic-client/src/playlist_detail.rs`, `crates/qqmusic-client/src/track_detail.rs`, `crates/provider-qqmusic/src/lib.rs`
- **R01–R10 + Rust shuffle extend:** `apps/flutter/test/discover/radar_convergence_test.dart`, `crates/music-domain/src/playback_queue.rs`
- **P01–P06:** `apps/flutter/test/library/collection_search_benchmark_test.dart`
