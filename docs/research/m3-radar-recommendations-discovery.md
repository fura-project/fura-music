# M3 QQ Radar Recommendations Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` implements `music.recommend.TrackRelationServer/GetRadarSong` with `Page`, `ReqType: 0`, empty `FavSongs`, and empty `EntranceSongs`. Its current typed response reads Tracks from `VecSongs[*].Track` and continuation from `HasMore`.
- simple-music commit `301d1ca159e88f6226acbc95fb01a28a99234e79` independently uses the same module/method as an authenticated QQ Radar route. It sends an auth-bearing `comm` plus Cookie, maps `VecSongs[*].Track`, pages by `Page`/`HasMore`, deduplicates by Track identity, and bounds its aggregate loop. Its documentation says page 1 previously returned one seed Track and later pages about ten; that row-count observation is historical rather than a stable contract.
- A bounded anonymous real-service probe sent the L-1124 parameter shape with only a lightweight `ct: 24`, `cv: 0` common block. It supplied no Cookie, token, stored credential, user identifier, query, or user data. Pages 1 and 2 both returned zero global/module codes, ten `VecSongs` rows with valid minimum Track identity/display shape, and `HasMore: true`.
- The two probed pages had one Track-identity overlap. Page progression must therefore follow service `Page`/`HasMore`, while presentation or queue handoff deduplicates provider/opaque Track identity without treating row count as a cursor. The current ten-row first page also proves that the older one-seed-row observation must not be encoded as a protocol invariant.
- The probes printed only codes, key names, row counts, field-shape validity, continuation, and overlap count. They did not print, retain, or commit Track identity, title, Artist, Album, artwork, response body, source URL, or account material.

Reference implementations remain research evidence only. Runtime requests will go directly to QQ Music, and no third-party server or raw response model becomes a project dependency.

## Ranked candidates

### 1. Authenticated QQ Radar recommendations — selected

- Goal: let the signed-in user browse a bounded QQ Radar Track feed and hand any loaded Track to the existing Rust-backed queue/playback path.
- Provenance: `ROADMAP.md` M3 evidence-backed QQ Music home/recommendation direction; two current independent implementations; the bounded anonymous two-page probe above; and the existing Track mapping, credential lifecycle, queue, and Discover surface.
- Scope: one provider-neutral paged Radar Track result; direct credential-bearing QQ request; exact Provider credential/replacement/rejection checks; one small Provider contract; one single-use cancellable typed Bridge operation; an independently retained Radar choice in Discover; and existing play/queue actions.
- Acceptance: exact request and redacted credential transport, global/module codes, `VecSongs[*].Track`, `Page`/`HasMore`, overlapping-page deduplication, authentication/replacement/rejection, first/empty/error/retry/pagination/append-failure/cancel/stale/disposal state, compact adaptive navigation, and queue handoff have offline regressions. Strict Rust/Dart checks, Flutter tests, Linux packaging, and packaged Bridge integration pass.
- Expected modules: `music-domain`, `provider-api`, `qqmusic-client`, `provider-qqmusic`, `bridges/flutter`, and the existing Flutter Discover/queue surface plus focused tests and generated bindings.
- Required tests: client request/response fixtures and redaction, Provider credential/error/replacement mapping, Bridge cancellation/redaction, Dart gateway/controller lifecycle and cross-page deduplication, compact Discover selection, Track play/queue handoff, full offline suites, Linux Release, and packaged typed-Bridge smoke.
- Known risks: the anonymous probe proves current structural compatibility but not authenticated personalization. The two references disagree on whether credentials are required by the raw endpoint, so the product route will require the already authenticated session and send the existing credential form without claiming recommendation quality or anonymous equivalence.
- Explicit non-goals: an endless autoplay radio, recommendation-quality claims, like/dislike feedback, a heterogeneous Home feed, daily-song aggregation, new queue semantics, background playback, availability/quality inference, Search expansion, comments, MV, mutation, or a generic recommendation runtime.

### 2. “Guess You Like” Track recommendations — deferred

- Provenance: the same M3 recommendation direction and both current references.
- Evidence gap: the current endpoint returns a much smaller batch and one reference loops multiple calls to synthesize a larger list. Radar has explicit service pagination, current two-page shape evidence, and a clearer bounded controller contract.

### 3. Heterogeneous QQ Music Home feed — deferred

- Provenance: `ROADMAP.md` M3 home/recommendation direction.
- Evidence gap: current Home shelves remain heterogeneous and carry volatile card, editorial, and tracking shapes. Implementing a mixed shelf runtime would be substantially broader than the selected Track feed and is not justified by the existing product model.

## Selection

Authenticated QQ Radar ranks first because it is a QQ-native recommendation route with two current implementations, live structural/pagination evidence, and a finite handoff into the already proven Track queue owner. The one observed cross-page duplicate supplies a concrete correctness requirement. This slice does not authorize a recommendation engine, a generic Home schema, or new playback semantics.
