# M3 Now-Playing Catalog Navigation Discovery — 2026-08-27

## Evidence

Every current QQ Track producer and the Rust-backed queue now retain an optional validated provider-neutral Album plus every validated credited Artist. Search and playlist-detail rows can already open these existing Album/Artist routes, but the global `NowPlayingBar` renders the current Track on the library, Search, Discover, playlist, ranking, Album, Artist, and favorite-Album surfaces without any catalog action. The gap is reproducible offline and requires no new QQ request, identity parsing, Domain value, Bridge DTO, queue rule, credential access, or dependency.

All authenticated product pages are presentation-local descendants of `UserLibraryPage`, which already owns the Album/Artist gateways, the one shared queue/playback controller, platform/AppBar back dispatch, and retained page overlays. Eight existing `NowPlayingBar` instances consume the same queue owner. A presentation-only inherited callback boundary can therefore connect the repeated bar instances to one new bounded overlay above every existing route without changing each feature controller or introducing a navigation framework.

## Global ranking

### 1. Current Track to Album/credited Artist — selected

- Provenance: M3 Album/Artist browsing and catalog coherence, the queue's already-validated context, and the reproduced unreachable-current-Track gap on every current surface.
- User value: while music continues, a user can browse the current Track's Album or one credited Artist from any base product page, then return to the exact underlying page and state.
- Scope: one optional presentation callback scope around the existing authenticated page tree; one adaptive bounded chooser from the now-playing artwork; one topmost retained Artist overlay and one optional nested Album; exact platform/AppBar return; existing Album/Artist controllers and shared playback owner.
- Acceptance criteria: no validated context means no action; one possible destination opens directly; Album plus Artists or collaborations require explicit selection; opening Artist may nest one existing Album; return unwinds Album → Artist → exact origin; no underlying controller reloads; current playback/queue ownership survives; narrow touch and desktop pointer/keyboard semantics have regressions; full static/offline/Linux checks pass.
- Risk: medium. The overlay must sit above every existing local route and must not reuse state whose return meaning depends on the underlying origin.
- Explicit non-goals: recursive route history, changing the current Track, per-row actions across every catalog surface, navigation while a modal is already open, biography/follow, protocol/Domain/Bridge/queue changes, or a navigation framework.

### 2. Favorite Artists — deferred

- Provenance: richer QQ library direction.
- Evidence gap: current public implementations disagree on response routing/pagination, the anonymous operation returns no data, and the proven response model does not provide the positive numeric Artist ID required by the selected Artist Track route. Stored account credentials remain out of bounds for autonomous discovery.

### 3. Track availability and quality representation — deferred

- Provenance: explicit M3 direction and the pending M1 playback evidence boundary.
- Evidence gap: no sanitized unavailable, region-filtered, VIP entitlement, or alternative-quality row behavior exists. Inferring entitlement from a failed playback request would collapse distinct protocol states.

### 4. Platform validation — environment-blocked

- Provenance: TD-004 and existing cross-platform claims.
- Evidence gap: Apple/Windows runtimes and a physical Android target are not available on the current host. Linux and Android-emulator evidence cannot be promoted into those claims.

## Selection

Now-playing catalog navigation ranks first because it closes a visible coherence gap using already-validated context and already-implemented routes. The ownership audit proves a finite presentation-only solution: one callback scope for eight real consumers and one topmost bounded overlay, rather than per-page state duplication or a new navigation system.

## Outcome

Implemented as the eighteenth finite M3 slice. One presentation-only inherited callback scope wraps every existing authenticated local page and routes its repeated now-playing bars into a topmost retained Artist/Album overlay. Validated single destinations open directly; Album plus Artists or collaborations use an adaptive bounded chooser. The new overlay is outside that callback scope, so it cannot recursively open another current-Track route. AppBar and platform back unwind nested Album → Artist → the exact underlying page without rebuilding its controller or replacing the shared queue/playback owner.

The now-playing artwork remains a plain image when the current Track has no validated context. When actionable, its compact size is 48 px and it exposes one precise semantic label, keyboard focus, and pointer/touch activation. A chooser selection is accepted only if the queue still has the same current position and Track identity and the selected context still belongs to that current Track; media shortcuts can therefore change playback while the chooser is open without routing to stale catalog data.

Validation on the current Linux host passed strict Dart formatting/analysis, all 276 Flutter tests, the Linux x64 Release build, and the packaged in-process Bridge integration. Rust was unchanged, and the existing 258-test offline workspace plus strict all-target/all-feature Clippy baseline was rerun successfully; four live QQ/WeChat tests remained explicitly gated and ignored. No real credential, QQ endpoint, media source, or account data was used.
