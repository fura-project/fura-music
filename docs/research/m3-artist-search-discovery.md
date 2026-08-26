# M3 Direct Artist Search Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` models typed Search through `music.search.SearchCgiService`, identifies Artist search as type `1`, and maps numeric Artist ID, MID, name, artwork, and catalog counts.
- Yyyangshenghao/simple-music commit `301d1ca159e88f6226acbc95fb01a28a99234e79` independently implements Artist search with `music.search.SearchCgiService/DoSearchForQQMusicDesktop`, `search_type: 1`, `page_num`, and `num_per_page`, and reads `body.singer.list`.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330` independently maps type `1` Search rows into Artist results. Its public synthetic fixture contains numeric Artist ID, MID, name, artwork, and catalog-count fields.
- A bounded anonymous real-service probe used the Desktop request without Cookie, token, stored credential, or user data. Page one returned five requested rows with current page `1`, next page `2`, total `8`, and per-page `5`; page two returned three rows with current page `2`, next page `-1`, and the same total. A terminal page-three check returned zero rows.
- Every observed row carried a usable positive numeric Artist ID, nonblank MID, and nonblank name. Page-one and page-two identity sets had zero overlap. The probe printed only codes, counts, field names/types, booleans, and overlap size; it did not print, retain, or commit the query, Artist identity, name, artwork, response body, or result content.

Reference implementations remain research evidence only. The runtime will call QQ Music directly and will not import third-party response models or depend on a third-party server.

## Ranked candidates

### 1. Direct Artist Search — selected

- Provenance: `ROADMAP.md` M3 Search and Artist directions plus a product-completeness audit of the implemented Artist Tracks/Albums journey.
- User value: users can find an Artist directly and browse both songs and albums without first finding a Track carrying that credit.
- Problem: the existing Search entry is Track-only even though the downstream Artist surface is now complete enough to be a first-class catalog destination.
- Scope: one provider-neutral paged Artist-search contract; direct bounded anonymous QQ request; Provider mapping to existing `ArtistSummary`; one single-use cancellable Bridge page handle; a Tracks/Artists Search type control with explicit first-page, empty, retry, pagination, append-failure, replacement, cancellation, stale-result, and disposal behavior; and direct handoff to the existing Artist page while preserving each Search type's local state.
- Acceptance: exact page/total/continuation and minimum Artist identity validation have offline regressions; empty or structurally invalid identities do not become actions; query replacement and type switching cannot surface stale results; returning Artist → Search restores the selected type and prior results; Artist Tracks/Albums and nested Album navigation reuse existing controllers and queue behavior; strict Rust/Dart checks, Flutter tests, Linux packaging, and packaged Bridge integration pass.
- Effort: high but finite.
- Risk: medium; the external Search metadata includes volatile tracing fields that must not enter Domain or Bridge, and two current method variants exist.
- Non-goals: Album/playlist/MV/user Search, mixed-result ranking, suggestions, history, hot words, Artist biography/follow, a generic union Search runtime, or a navigation/state-management framework.

### 2. QQ Music ranking lists — deferred

- Provenance: `ROADMAP.md` M3 QQ-native catalog-flow direction and current public Toplist references.
- User value: query-free chart discovery can feed the existing Track queue and complement recommended playlists.
- Problem: the product has recommendation discovery but no chart-oriented catalog entry.
- Scope: one list/detail pair only after period and identity semantics are bounded.
- Acceptance: a separate discovery must cross-validate list/detail request shapes, period selection, bounded Track mapping, and navigation before implementation.
- Effort: high.
- Risk: medium-high because periods and editorial metadata are externally controlled.
- Non-goals: chart history, third-party charts, heterogeneous Home shelves, or personalization.

### 3. Direct Album Search — deferred

- Provenance: `ROADMAP.md` M3 Search and Album directions plus current typed-Search implementations.
- User value: users can reach a known Album without relying on a matching Track row.
- Problem: the downstream Album Tracks page exists, while catalog Search cannot yet return Album destinations.
- Scope: one Album-only typed Search slice after its identity and pagination shape receive an independent bounded probe.
- Acceptance: exact pagination and Album identity/title/artwork mapping are evidenced and tested; opening a result reuses the existing Album page and preserves Search state.
- Effort: medium-high after Artist Search establishes the type-switch interaction.
- Risk: medium; it must remain a distinct typed result rather than force Track and Album rows into one speculative union model.
- Non-goals: playlist/MV Search, Album metadata expansion, mutation, or mixed-result ranking.

## Selection

Direct Artist Search ranks first because the real anonymous response supplies the exact numeric-ID/MID identity already required by both existing Artist operations, the requested page size and terminal continuation were honored, and the resulting user path is finite: Search → Artist Tracks/Albums → existing Album/queue. Rankings require a separate list/detail/period audit, while Album Search should reuse the interaction boundary proven by this smaller one-type expansion.

## Implementation outcome

Implemented on 2026-08-26 as the sixth finite M3 slice. The client uses the exact typed Desktop request and rejects invalid pagination or Artist identity before Domain mapping; Provider, Domain, and Bridge keep Artist identity opaque and diagnostics redacted. Flutter keeps Tracks and Artists in independent controllers, carries the current text only on a type's first visit, suppresses replacement and disposal races, and restores the selected Artist Search state after existing Artist and nested Album navigation. Rust formatting, 195 offline Rust tests, strict Clippy, strict Dart formatting/analysis, all 208 Flutter tests, the Linux x64 Release bundle, and packaged typed-Bridge integration pass. The four live QQ/WeChat tests remain gated, and no live application compatibility or authenticated downstream playback claim is made.
