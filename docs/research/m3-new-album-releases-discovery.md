# M3 New Album Releases Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10`, still the remote HEAD on 2026-08-26, implements `newalbum.NewAlbumServer/get_new_album_info` with `area`, `num`, and zero-based `start`. Its current typed response maps numeric total plus Album identity/title, credited Artists, release date, and artwork identity, and its live-gated tests exercise areas 1–3 plus two-page forward progress.
- A bounded anonymous real-service probe used only `ct: 24`, `cv: 0`, and `format: json`. Two area-1 requests with `num: 5` and starts 0/5 both returned zero global/module codes, exactly five minimum-shape Albums, numeric totals, and no Album-identity overlap.
- Six additional one-row anonymous requests established that current area values 1–6 all return zero codes, one minimum-shape Album, and a numeric total. These values correspond to Mainland China, Hong Kong/Taiwan, Western, Korea, Japan, and Other in the current implementation.
- The probes supplied no Cookie, token, stored credential, user identifier, query, or user data. They printed only area/code/count/type/shape booleans and overlap count; no Album or Artist identity, title, artwork, release text, response body, or account material was printed, retained, or committed.

Reference code and its live tests remain research evidence only. Runtime requests will go directly to QQ Music, and no third-party server or response model becomes a dependency.

## Ranked candidates

### 1. Regional new album releases — selected

- Goal: let a user browse current QQ Music new-album pages by the six evidenced regions and open an Album through the existing Album → Track → queue path.
- Task provenance: `ROADMAP.md` M3 QQ-native catalog/home and Album directions; the current independent implementation and live-gated pagination tests; the bounded anonymous area/pagination evidence above; and the existing Album page and Discover surface.
- User value: adds query-free, current catalog discovery without importing the volatile heterogeneous Home-card runtime or duplicating Album Track loading.
- Scope: a small provider-neutral new-release region and paged Album-release result; one direct anonymous QQ request; one Provider capability; one single-use cancellable typed Bridge page operation; a lazy New Albums choice in Discover with explicit region replacement; and handoff to the existing Album page and queue.
- Acceptance criteria: exact area/start/size request and global/module/data mapping; bounded pagination and minimum Album/Artist/release fields; invalid region/identity/continuation rejection; first/empty/error/retry/load-more/append-failure/cancel/stale/disposal and region-replacement state; compact reachable Discover/region controls; return preserves New Albums state; existing Album and queue owners are reused; full strict Rust/Dart checks, Flutter tests, Linux Release, and packaged Bridge integration pass.
- Expected modules/files: `music-domain`, `provider-api`, `qqmusic-client`, `provider-qqmusic`, `bridges/flutter`, generated bindings, the existing Flutter Discover/library navigation and Album gateway types, focused tests, and current architecture/state documentation.
- Required tests: client exact request/response/redaction and pagination fixtures; Provider mapping/error coverage; Domain/Bridge mapping and cancellation; Dart gateway/controller lifecycle including region replacement; compact selector and New Albums → Album → return widget flow; existing Album queue regression; full offline suites and packaged Linux validation.
- Known risk: release metadata and Artist rows are externally unstable; only the minimum evidenced fields may enter the Domain, and a row without valid Album identity/title must not become navigable.
- Explicit non-goals: heterogeneous Home shelves, editorial/tracking cards, new-album notifications, automatic refresh/cache, Album mutation/favorite actions, Album-detail metadata expansion, Track context navigation, Search changes, recommendation quality, new queue semantics, or a generic recommendation/catalog runtime.

### 2. Authenticated favorite Albums — deferred

- Provenance: M3 richer-library direction, L-1124's current `music.musicasset.AlbumFavRead/CgiGetAlbumFavInfo` implementation and authenticated live-gated test, plus FeelUOwn's independent legacy favorite-Album product path.
- Evidence gap: the exact current route has no secret-safe project observation, while New Albums has current anonymous shape and pagination evidence and can reuse Album browsing without adding another credential-bearing library lifecycle in the same slice.
- Non-goals: treating the deferred state as permission to automate against the user's stored credential or to add remote Album mutation.

### 3. Cross-surface Track-to-Album/Artist navigation — deferred

- Provenance: M3 Album/Artist and richer-library directions plus a reproduced code-level gap: ordinary Track summaries retain names but not catalog identities outside Search.
- Boundary gap: a correct solution affects the shared Track Domain, generated queue round-trip, every Track-producing Provider map, and navigation return origins. That is broader than a single UI affordance and needs its own bounded design pass rather than being attached to the nearest list row.
- Non-goals: adding Flutter-only protocol identities, parsing QQ opaque IDs in Dart, or introducing a navigation framework just to expose the actions.

## Selection

Regional new album releases rank first because the current direct operation has exact implementation evidence, repeatable live-gated pagination tests, bounded anonymous evidence across every exposed region, and a finite transition into the existing Album/queue path. It adds a distinctly QQ-native discovery surface while avoiding both credential access and a speculative heterogeneous Home abstraction.
