# M3 Artist Browsing Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements Artist songs with `musichall.song_list_server/GetSingerSongList`, Artist MID, `begin`, and `number`, and explicitly models offset pagination.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330` independently implements Artist songs with `music.musichallSong.SongListInter/GetSingerSongList`, numeric Artist ID, `begin`, `num`, and `newsong: 1`.
- A bounded anonymous probe selected one Artist identity only in memory from a generic five-row Track search. The MID/`number` operation returned two consecutive 30-row pages with global/module code `0`, a numeric total, matching Artist MID, forward progress, and no Track-identity overlap. The numeric-ID/`num` operation returned two consecutive five-row pages with the same coarse success and pagination properties while honoring the requested five-row bound exactly.
- The probe used no Cookie, token, stored credential, or user data. It printed only codes, counts, booleans, and overlap size; no Artist/Track identifier, title, URL, response body, or content was printed, retained, or committed.
- Search already returns Artist numeric ID, MID, and name. A bounded Artist page therefore does not require the separate detail operation that previously returned module code `10006`; biography, artwork, and other detail metadata remain outside this slice.

Reference implementations remain research evidence only. No third-party server, dependency model, or response fixture enters the runtime.

## Ranked candidates

### 1. Artist browsing from Track search — selected

- Provenance: `ROADMAP.md` M3 Artist direction, completed Track-search/Album transitions, two independent current implementations, and successful anonymous bounded pagination probes.
- User value: a user can move from a discovered Track to any credited Artist's song catalog and play it through the existing queue.
- Problem: Search currently retains Artist display names but discards the provider-owned numeric ID and MID required for a follow-up catalog operation.
- Scope: provider-neutral Artist summaries attached to Search items, direct offset-paged Artist Tracks using the exact-size numeric-ID request, one cancellable Bridge page operation, a bounded Artist selector for multi-Artist Tracks, an adaptive Artist Track page, preserved Search state, and existing queue/playback handoff.
- Acceptance: only validated Artist identities appear in the selector; one or multiple credited Artists remain distinguishable; initial/empty/error/retry/pagination/append-failure/cancel/stale/disposal states are explicit; returning preserves Search query/results; Track selection and queue append reuse the existing Rust queue; offline protocol, Provider, Domain, Bridge, controller, navigation, widget, strict-analysis, and Linux build checks pass.
- Effort: high but finite.
- Risk: medium; two live request shapes coexist, so the implementation must choose one evidenced envelope without merging their parameters or inferring detail metadata.
- Non-goals: Artist biography/artwork/detail, Artist albums, follow/favorite, similar Artists, MV/video, Artist search result type, Home, quality selection, a navigation framework, or a generic catalog runtime.

### 2. QQ Music Home and recommendations — deferred

- Provenance: `ROADMAP.md` M3 Home/recommendation direction.
- User value: a content-driven everyday landing surface.
- Current evidence gap: section composition, personalization, cache/refresh continuation, stable section identity, and signed-out/authenticated differences remain more volatile than the bounded Artist transition.
- Effort: high.
- Risk: high.
- Non-goals: copying the official homepage or creating a generic recommendation framework before stable shapes exist.

### 3. Track availability and quality representation — deferred

- Provenance: `ROADMAP.md` M3 availability/quality direction and the existing playback evidence boundary.
- User value: explains why a Track cannot play and which quality is actually selected.
- Current evidence gap: the checkout has no sanitized unavailable/region/VIP action-row fixture, and authenticated playback acceptance remains locally pending. Guessing action-bit or file-size semantics would spread an unverified rule into Domain and UI.
- Effort: medium after evidence exists.
- Risk: high without representative response evidence.
- Non-goals: inferring VIP/region status from one failed source resolution or adding quality selection from file metadata alone.

## Selection

Artist browsing ranks first because it extends the implemented Search catalog with high user value, both identity forms are already present, two current independent implementations exist, and both anonymous pagination paths advanced repeatably. The numeric-ID/`num` request is selected because it honored the requested bound exactly; the MID/`number` path remains independent behavioral corroboration. Home and availability remain authorized candidates, not implementation commitments.

## Implementation outcome

Completed on 2026-08-26 within the selected boundary. Search retains every validated credited Artist as a provider-neutral summary, while `QQMusicProvider` alone owns the opaque numeric-ID/MID representation. The direct client operation validates bounded offset pagination and maps only the established minimum Track shape. A single-use cancellable Bridge page operation feeds a Flutter controller with explicit first-page, empty, retry, append-failure, replacement, stale-result, and disposal behavior. Collaborations expose an explicit Artist selector; opening one Artist keeps Search mounted, and returned Tracks reuse the existing Rust-backed queue.

Validation passed for 175 offline Rust tests, strict Clippy, strict Dart analysis, 181 Flutter tests, Linux x64 Release packaging, and the packaged Linux typed-Bridge integration. Four live QQ/WeChat tests remained separately gated and ignored. This evidence proves local mapping, lifecycle, presentation, navigation, queue handoff, and packaged Bridge behavior; it does not prove current live Artist compatibility or real-account search-to-CDN playback. No Artist detail, biography, artwork, albums, follows, Home, quality, new Provider, navigation framework, or generic catalog runtime was added.
