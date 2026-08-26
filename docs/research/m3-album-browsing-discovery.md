# M3 Album Browsing Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements `music.musichallAlbum.AlbumInfoServer/GetAlbumDetail` and offset-paged `music.musichallAlbum.AlbumSongList/GetAlbumSongList` for either Album ID or MID.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330` independently presents Album detail and songs, but its Album transport is a legacy endpoint. This supports the product behavior, not exact cross-validation of the current musicu request.
- A bounded anonymous probe selected an Album MID only in memory from a generic Track-search result, then called both current musicu operations. Detail returned global/module code `0` and the expected top-level data groups. A five-row song request returned global/module code `0`, five wrapped song rows, a numeric total, and the same Album MID. No Album, Track, Artist, URL, or response content was printed, retained, or committed.
- The Album-song rows use the same minimum Track shape already mapped by playlist detail and Track search. Album MID is already present in the raw Track-search response but is currently discarded at the Provider boundary.

Reference implementations remain research evidence only. No third-party server, dependency model, response fixture, or copied product behavior enters the runtime.

## Ranked candidates

### 1. Album browsing from Track search — selected

- Provenance: `ROADMAP.md` M3 Album browsing direction, the implemented Track-search entry point, one current implementation, and a successful anonymous protocol probe.
- User value: a user can move from a discovered Track into its Album and play the Album in order without returning to their own library.
- Problem: Search currently preserves only Album display text; it discards the provider-owned identity needed for a bounded follow-up operation.
- Scope: optional provider-neutral Album summary attached to a Track-search item, direct offset-paged Album songs, one cancellable Bridge page operation, adaptive Album Track page, local return to the existing Search results, and the existing queue/playback handoff.
- Acceptance: only results with a valid Album identity expose the action; initial/empty/error/retry/pagination states are truthful; replacement/disposal suppress stale pages; returning preserves the Search query/results; selecting or appending a Track delegates to the existing Rust queue; offline protocol, Provider, Domain, Bridge, controller, navigation, and primary widget-flow tests pass.
- Effort: high but finite.
- Risk: medium; Album Track mapping repeats an externally unstable song shape and must not turn Album into a playlist alias.
- Non-goals: Album description/company/release metadata, Album favorites or mutation, Album-type search results, Artist browsing, comments, MV, quality selection, a navigation framework, or a generic catalog runtime.

### 2. Artist browsing from Track search — deferred

- Provenance: `ROADMAP.md` M3 Artist browsing direction and two current implementations of Singer detail/song behavior.
- User value: moves from a discovered Track to an Artist catalog.
- Current evidence gap: the anonymous `GetSingerSongList` probe succeeded but returned 30 rows after requesting five, while the bounded `GetSingerDetail` probe returned module code `10006`. Platform/common-parameter and page-size semantics therefore need a separate discovery task before implementation.
- Effort: high.
- Risk: medium-high until detail and pagination behavior are resolved without guessing.
- Non-goals: treating the successful oversized response as permission to silently ignore requested bounds.

### 3. QQ Music Home and recommendations — deferred

- Provenance: `ROADMAP.md` M3 Home/recommendation direction.
- User value: a content-driven everyday landing surface.
- Current evidence gap: section composition, personalization, cache/refresh inputs, and stable section identity remain more volatile than the bounded Album path.
- Effort: high.
- Risk: high.
- Non-goals: copying an entire official homepage or inventing a generic recommendation-section framework before stable shapes exist.

## Selection

Album browsing ranks first because the current Search result already contains its identity, the direct Album-song operation honored the requested bound in the anonymous probe, and the result can reuse the existing Track/queue path. Artist and Home remain authorized candidates, not implementation commitments for this slice.

## Implementation outcome

Completed on 2026-08-26 within the selected boundary. Search now retains optional provider-neutral Album identity; `QQMusicClient` implements the bounded Album-song operation; `QQMusicProvider` maps it through the small Catalog contract; the generated Bridge exposes one exact cancellable page handle; and Flutter owns the adaptive Album page while preserving the mounted Search state and existing queue owner. Offline Domain/client/Provider/Bridge/controller/navigation/widget coverage, strict analysis, the Linux x64 Release build, and packaged typed-Bridge cancellation integration pass. This does not establish live Album compatibility or authenticated CDN playback, and the deferred Artist/Home evidence gaps remain unchanged.
