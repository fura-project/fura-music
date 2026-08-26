# M3 Album Artist Navigation Discovery — 2026-08-27

## Evidence

Canonical Album details already return every validated provider-neutral credited `ArtistSummary`, and `AlbumPage` already renders their names. The same authenticated application owner also already provides the Artist Tracks/Albums route, the nested Album route, one shared Rust-backed queue/playback owner, and retained local overlays. The current gap is presentation routing: rendered Album credits are not actionable from Search Albums, Artist discography Albums, regional new Albums, favorite Albums, or playlist Track context Albums.

No QQ protocol request, identity parsing, credential access, Provider contract, Bridge DTO, dependency, or new product category is required. The data was introduced by the completed canonical Album-details slice and the route is explicitly within the M3 Album/Artist browsing direction.

## Global ranking

### 1. Album metadata to credited Artist navigation — selected

- Provenance: M3 Album/Artist browsing, existing validated Album-detail credits, and the reproduced unreachable-credit gap on every current Album origin.
- User value: a user can open any credited Artist from an Album, browse that Artist's Tracks/Albums, open one nested Album, and return to the exact originating Album and collection.
- Route audit: all four concrete `AlbumPage` instances are owned by `UserLibraryPage`; one bounded outer Artist overlay and one nested Album overlay can sit above the existing Favorite, Discover, Search, Artist, and playlist-origin stacks without replacing any underlying controller.
- Acceptance criteria: the action appears only after canonical details supply valid credits; one credit opens directly and collaborations require explicit bounded selection; every current Album instance receives the callback; platform/AppBar return unwinds nested Album → credited Artist → originating Album → original collection; queue/playback ownership and underlying loaded state survive; focused navigation/UI regressions plus full static/offline/Linux checks pass.
- Risk: medium. Cyclic catalog navigation must remain bounded and cannot reuse a state variable whose meaning depends on the underlying origin.
- Explicit non-goals: Artist action before details load or after detail failure, Track-row actions outside playlist detail, global now-playing navigation, recursive unbounded route history, Artist biography/follow, Album mutation, protocol changes, caching, or a navigation framework.

### 2. Global now-playing catalog navigation — deferred

- Provenance: M3 catalog coherence and the newly retained queue Album/Artist context.
- User value: catalog navigation would be reachable regardless of the visible feature page.
- Evidence gap: the global now-playing surface spans every local overlay plus dialogs/sheets and needs a separate ownership and return audit. Reusing this task's bounded Album route as an implicit global route would expand scope.

### 3. Track availability and quality representation — deferred

- Provenance: explicit M3 direction and the pending M1 playback evidence boundary.
- Evidence gap: the repository still lacks sanitized unavailable/region/VIP action-row evidence, and the corrected authenticated playback path still awaits user observation. Inferring entitlement or quality semantics remains unsafe.

## Selection

Album-to-Artist navigation ranks first because it turns already-validated, already-rendered canonical metadata into a coherent existing catalog path for every Album origin. It is a finite product connection rather than visual polish, introduces no external dependency or protocol uncertainty, and can be proven with the current offline and packaged test environment.

## Implementation outcome — 2026-08-27

The selected slice is complete. `AlbumPage` exposes an optional action only after canonical details provide nonempty validated credits, opens one Artist directly, and presents a bounded bottom sheet or desktop dialog for collaborations. All four pre-existing Album instances receive the same callback; a separate outer Artist state and one nested Album state retain Favorite, Discover, Search, existing Artist, and playlist context beneath them.

Focused regressions cover single and multi-credit selection, callback injection at every concrete Album origin, and the representative Album → Artist → nested Album → Artist → original Album/Search return chain without a second original-Album load. The full Flutter suite and Linux packaged Bridge path pass. No Rust, Provider, Bridge, credential, protocol, dependency, queue rule, or navigation framework changed.
