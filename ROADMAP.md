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
- **Album browsing:** implemented as the second finite M3 slice on 2026-08-26 after current implementation evidence and a bounded anonymous Album detail/song probe. Search items retain an optional provider-neutral Album identity; a direct bounded QQ operation returns paged Album Tracks through a cancellable Bridge; and adaptive Flutter navigation preserves Search state while reusing the existing queue. Full Album metadata, mutation, mixed-result Search, and a broad catalog abstraction remain out of scope.
- **Artist browsing:** implemented as the third finite M3 slice on 2026-08-26 after two current independent request shapes and bounded anonymous pagination probes. Search items retain all validated provider-neutral credited Artist identities; a direct exact-size QQ operation returns offset-paged Artist Tracks through a cancellable Bridge; explicit multi-Artist selection preserves collaborations; and adaptive Flutter navigation preserves Search state while reusing the existing queue. Artist biography/artwork/details, follows, Home, quality selection, and a broad catalog abstraction remain out of scope; Albums were added by the later fifth slice.
- **Recommended playlists:** implemented as the fourth finite M3 slice on 2026-08-26 after two current independent implementations and bounded anonymous exact-size/pagination probes. A direct public QQ operation maps offset-paged `PlaylistSummary` rows through a small Recommendations contract and cancellable Bridge; adaptive Flutter discovery preserves state while opening the existing authenticated playlist-detail and queue path. Pagination advances by raw page length rather than treating the observed `FromLimit` bound as a cursor. Heterogeneous Home cards, personalization claims, radio/daily recommendations, rankings, mutation, and a generic recommendation runtime remain out of scope.
- **Artist albums:** implemented as the fifth finite M3 slice on 2026-08-26 after two current independent implementations and bounded anonymous parameter/pagination probes. A direct public Artist-Album operation maps exact-size offset pages into existing `AlbumSummary` values through a small Catalog contract and cancellable Bridge; the existing Artist page loads an adaptive Albums section lazily, preserves both sections, and nests the existing Album/queue path. The request uses the real-service `num` page-size field rather than the conflicting ignored `number` reference. Biography/artwork/follow, discography filters, mixed-result Search, rankings, and a generic catalog runtime remain out of scope.
- **Direct Artist Search:** implemented as the sixth finite M3 slice on 2026-08-26 after three current implementation/fixture references and a bounded anonymous exact-size/terminal-page probe. A separate provider-neutral Artist-search page maps the Desktop type-1 operation into existing opaque `ArtistSummary` values through a cancellable Bridge. Flutter preserves independent Tracks/Artists query and result state, hands direct results to the existing Artist Tracks/Albums and nested Album/queue path, and does not introduce a mixed Search union or navigation framework. MV/user Search, suggestions/history/hot words, biography/follow, and generic Search infrastructure remain out of scope; Album and Playlist Search were added by the later seventh and ninth slices.
- **Direct Album Search:** implemented as the seventh finite M3 slice on 2026-08-26 after two current independent implementations and a bounded anonymous five-page exact-size/terminal probe. A separate provider-neutral Album-search page maps the Desktop type-2 operation into existing opaque `AlbumSummary` values through a cancellable Bridge. Flutter preserves independent Tracks/Artists/Albums query and result state, hands direct Album results to the existing Album Tracks/queue path, and keeps the 360px control usable without adding a mixed Search union or navigation framework. MV/user Search, suggestions/history/hot words, Album metadata expansion/mutation, and generic Search infrastructure remain out of scope; Playlist Search was added by the later ninth slice.
- **Current QQ ranking lists:** implemented as the eighth finite M3 slice on 2026-08-26 after two independent current implementations and bounded anonymous list/two-page detail probes. Direct anonymous QQ list/detail operations map grouped summaries and paged Tracks through a small provider-neutral Rankings contract and cancellable Bridge. Flutter preserves independent Playlists/Rankings discovery state, opens the current ranking, and reuses the existing queue. Period remains optional display metadata and `topId` always resolves the service's current period; history selection, subscriptions, third-party charts, heterogeneous Home cards, and generic recommendation/catalog infrastructure remain out of scope.
- **Direct Playlist Search:** implemented as the ninth finite M3 slice on 2026-08-26 after two current source/fixture references and a bounded anonymous three-page Desktop probe. A separate provider-neutral Playlist-search page maps the Desktop type-3 operation into existing opaque `PlaylistSummary` values through a cancellable Bridge. Flutter preserves independent Tracks/Artists/Albums/Playlists state, keeps the compact four-type control horizontally reachable, and opens the existing public playlist-detail/queue path without reloading Search. Service `nextpage`, not returned row count, owns continuation because one observed nonterminal five-row request returned four rows. Mixed Search, creator profiles, history/suggestions/hot words, playlist mutation, and generic Search/navigation infrastructure remain out of scope.
- **Authenticated QQ Radar recommendations:** implemented as the tenth finite M3 slice on 2026-08-26 after two current independent implementations and a bounded anonymous two-page structural probe. A direct credential-bearing Radar operation maps `VecSongs[*].Track` into provider-neutral page-numbered Tracks through a cancellable Bridge. Service `Page`/`HasMore` owns continuation, while Flutter preserves independent Playlists/Rankings/Radar state, deduplicates the observed provider/opaque identity overlap, cleans the shared vault only after explicit credential rejection, and delegates play/add actions to the existing queue. Anonymous evidence does not establish personalization or recommendation quality; endless autoplay, feedback, heterogeneous Home shelves, daily-song aggregation, new queue semantics, and generic recommendation infrastructure remain out of scope.
- **Regional new album releases:** implemented as the eleventh finite M3 slice on 2026-08-26 after a current direct implementation, its live-gated pagination tests, and bounded anonymous two-page plus six-region structural probes. A direct public operation maps typed region/offset pages into provider-neutral Album releases with credited Artists and optional release date through a cancellable Bridge. Flutter keeps New Albums as a fourth lazy retained Discover state, replaces region requests exactly, adapts list/grid presentation, and opens the existing Album/Track/queue route without reloading prior state. Heterogeneous Home shelves, editorial/tracking cards, notifications/cache, Album mutation or detail expansion, Track context navigation, and generic recommendation/catalog infrastructure remain out of scope.
- **Existing Album-page metadata:** implemented as the twelfth finite M3 slice on 2026-08-26 after a current direct implementation/live-gated test, bounded anonymous exact-request and field-shape probes, and an independent legacy product path. A direct public operation maps exact Album MID into provider-neutral canonical Album/Artist identity plus bounded optional display metadata through a cancellable Bridge. Flutter loads it independently beside Tracks, keeps Track/queue use available on detail failure, retries explicitly, and presents the complete description through adaptive compact/desktop surfaces for every existing Album origin. Album favorites/mutation, booklet/wiki/video/rights/tracking fields, Artist navigation, Track identity propagation, cache, and generic catalog/navigation infrastructure remain out of scope.
- **Authenticated favorite Albums:** implemented as the thirteenth finite M3 slice on 2026-08-26 after two current independent implementations, a real-account failure record for the tempting musicu route, and a bounded no-Cookie authentication-shape probe. A direct legacy profile-asset request maps strict offset pages into existing opaque `AlbumSummary` values through exact Provider credential candidate/rejection/replacement rules and a cancellable Bridge. Flutter retains an adaptive collection while the existing Album Tracks/details/queue path is open, paginates and retries explicitly, and cleans the shared vault only for the evidenced global rejection code. Favorite mutation, favorite Artists, cache/automatic refresh, a generic library union, Track context navigation, and generic navigation infrastructure remain out of scope.
- **Playlist Track-to-Album navigation:** implemented as the fourteenth finite M3 slice on 2026-08-26 after a repository-wide mapping audit proved that the common QQ Track response already carried valid Album identity which non-Search surfaces discarded. Shared Domain, Bridge, Dart, and Rust queue values now preserve optional same-Provider Album context without parsing opaque Track identity. Existing playlist-detail origins expose the existing Album route through bounded desktop keyboard/mouse and mobile long-press actions, while retained local presentation preserves loaded playlist and playback state on return. Credited-Artist context, actions on other Track surfaces, global now-playing catalog navigation, new queue semantics, and generic navigation infrastructure remain out of scope.
- **Playlist Track-to-Artist navigation:** implemented as the fifteenth finite M3 slice on 2026-08-27 after the shared Track audit proved that every QQ Track response already carried credited Artist identities which the common Provider mapper discarded. Shared Domain, Bridge, Dart, and Rust queue values now preserve every validated same-Provider credit; playlist-detail context surfaces open one credit directly or require explicit collaboration selection. The retained Artist route can nest the existing Album route and returns Album → Artist → playlist without reloading the originating playlist or replacing playback ownership. Album-metadata links, actions on other Track surfaces, global now-playing navigation, biography/follow, new queue semantics, and generic navigation infrastructure remain out of scope.
- **Album metadata-to-Artist navigation:** implemented as the sixteenth finite M3 slice on 2026-08-27 from canonical Album details that already supplied validated credited Artists. Every pre-existing Album origin exposes one credit directly or requires explicit bounded collaboration selection, then retains an Artist and one nested Album above the exact originating Album/collection. Platform and AppBar return unwind nested Album → Artist → originating Album without reloading underlying state or replacing the shared playback owner. Pre-detail actions, recursive route history, global now-playing navigation, biography/follow, protocol changes, and generic navigation infrastructure remain out of scope.
- **Typed QQ new-song channels:** implemented as the seventeenth finite M3 slice on 2026-08-27 after two current independent direct implementations and a bounded anonymous category/field-shape probe. A direct public `newsong.NewSongServer/get_new_song_info` operation maps six exact service categories and one bounded whole-response Track collection through a small provider-neutral Catalog contract and cancellable Bridge. Flutter keeps New Songs as a fifth lazy retained Discover state, replaces categories exactly, keeps all categories reachable at 360px, and delegates play/add actions to the existing queue. No pagination is invented; heterogeneous Home shelves, editorial tags, personalization or quality claims, radio/autoplay, cache, new queue semantics, and generic recommendation infrastructure remain out of scope.
- **Current Track catalog navigation:** implemented as the eighteenth finite M3 slice on 2026-08-27 from the already-validated Album and credited-Artist context retained by every queue Track. One presentation-only callback scope connects every existing now-playing bar to a topmost retained Artist/Album overlay; single destinations open directly, collaborations use an adaptive bounded chooser, and platform/AppBar return restores the exact originating page and controller state. A modal selection is discarded when playback moves to a different queue position or context. Recursive route history, protocol/Domain/Bridge/queue changes, per-row expansion, and generic navigation infrastructure remain out of scope.
- **Adaptive immersive now playing:** implemented as the nineteenth finite M3 slice on 2026-08-27 from the explicit `PROJECT.md` core-experience requirement and a reproduced missing full current-Track surface. One presentation-only callback opens a retained topmost page from every existing bar; wide layout pairs large artwork with the existing synchronized lyric panel, compact layout stacks them, and the unchanged bar preserves transport/queue/volume behavior. Queue replacement updates in place, queue clearing is explicit, and AppBar/platform return restores the exact origin. Palette extraction, gestures, background playback, mini-player/audio/queue rewrites, protocol/Domain/Bridge changes, and navigation infrastructure remain out of scope.

## Later direction

After coherent QQ Music core coverage, evaluate deeper platform integration and evidence-backed offline/cache behavior. Narrow local-library or media-fallback capabilities come later and require demonstrated user value; they must not turn the product into a multi-source aggregator.
