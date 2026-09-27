# Provider parity and improvement audit

Date: 2026-09-24. Execution: `AUTONOMOUS_DEVELOPMENT / MIXED`.
Gate: `HUMAN_REVIEW`.

This is a current-source, capability-by-capability comparison of Fura's QQ
Music and NetEase Cloud Music integrations plus the not-yet-production KuGou
Music provider. It is not an endpoint-import plan. A third-party implementation
is protocol evidence, not automatic product scope or permission to copy code.

No QQ, NetEase or KuGou service request was made for this audit. Current source
repositories were inspected, deterministic fixtures were added, and the
previously authorized KuGou public-read window remains closed at 40/40. No
real-account write was attempted. Existing uncommitted KuGou Search, exact
Track detail, Ranking and line-timed LRC work was preserved.

## Classification

Capability evidence uses these states:

- `CURRENT_FURA_PRIMARY`: Fura's current primary implementation.
- `CURRENT_FURA_COMPAT`: retained compatibility or rollback implementation.
- `THIRD_PARTY_CORROBORATED`: current external sources agree, but that alone is
  not a production decision.
- `EVIDENCE_READY`: independent current evidence is sufficient for an
  implementation whose remaining validation is offline.
- `HUMAN_LIVE_REQUIRED`: an account, write, entitlement or bounded live probe
  is still required.
- `PRODUCT_DECISION_REQUIRED`: the protocol exists, but its product/domain/UI
  meaning has not been accepted.
- `EVIDENCE_BLOCKED`: evidence is contradictory, derivative-only, unsafe or
  incomplete.
- `REJECTED`: conflicts with Fura's identity, security or ownership rules.

Changes use `SAFE_LOW_RISK_OPTIMIZATION`,
`EVIDENCE_READY_PROTOCOL_CHANGE`, `OFFLINE_FOUNDATION_ONLY`,
`HUMAN_LIVE_REQUIRED`, `PRODUCT_DECISION_REQUIRED`, `NO_CHANGE`, or
`REJECTED`.

## PROVENANCE_GRAPH

### QQ Music

| Source | Exact current commit / activity | License | Role and independence | Fura boundary |
| --- | --- | --- | --- | --- |
| [L-1124/QQMusicApi](https://github.com/L-1124/QQMusicApi/tree/ba95861ee9391f5b5f60f89caa8d4de4af160c8b) | `ba95861e`, 2026-09-18 | GPL-3.0 | Active direct API implementation. Its product users are not additional wire votes. | Observe wire behavior only; no code translation. |
| [yakult-green-tea/qq-music-api](https://github.com/yakult-green-tea/qq-music-api/tree/b369be4ab8e0a7b6bdfba971e107faeccae3541f) | `b369be4a`, 2026-09-12 | MIT | Active direct implementation, independent corroboration for overlapping operations. | Protocol/behavior evidence; implement independently. |
| [jsososo/QQMusicApi](https://github.com/jsososo/QQMusicApi/tree/13b08afd3180cc74d76fff208956b77a560abd22) | `13b08afd`, 2022-07-09 | GPL-3.0 | Historical direct baseline; materially older than the active sources. | Secondary history only. |
| [Yyyangshenghao/simple-music](https://github.com/Yyyangshenghao/simple-music/tree/353caf01c4ccf638c00c2caa4785a82ab3331b77) | `353caf01`, 2026-09-13 | GPL-3.0 | Active real product. QQ implementation is direct; its NetEase support is package-backed and is not an independent NetEase wire vote. | Product behavior and wire observation only. |
| [feeluown/feeluown-qqmusic](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330) | `241a9678`, 2026-03-26 | No top-level license located in this audit | Active real-product plugin and direct QQ implementation. | Evidence-only unless licensing is clarified. |

The active sources do not unanimously select one Search profile. L-1124 uses
the mobile Android `DoSearchForQQMusicMobile` family, while current FeelUOwn,
Simple Music and Fura retain desktop-style search. Fura also has real code-2001
risk evidence. Activity alone is therefore not a reason to rotate profiles.

### NetEase Cloud Music

| Source | Exact current commit / activity | License | Role and independence | Fura boundary |
| --- | --- | --- | --- | --- |
| [NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/tree/a8c781fd64faab17fedfd46e0615a2609307f163) | `a8c781fd`, 2026-09-12 | MIT | Active Binaryify-lineage direct API. | Primary current reference, not independent of its ports. |
| [SPlayer-Dev/ncm-api-rs](https://github.com/SPlayer-Dev/ncm-api-rs/tree/133b65bfe482e41ebccf018870d3fce07bf58eb3) | `133b65bf`, 2026-04-07 | WTFPL | Declares itself a one-to-one Rust port of API Enhanced. | Same wire vote as Enhanced. |
| [go-musicfox/go-musicfox](https://github.com/go-musicfox/go-musicfox/tree/12169a71098f8b8607bcf655eaddabf57ca14daf) | `12169a71`, 2026-09-07 | GPL-3.0 | Active real product with a vendored Go direct client derived from the older `NeteaseCloudMusicApiWithGo` lineage. Independent implementation work, though many route concepts share historical NCM API ancestry. | Product and wire evidence only; no code translation. |
| [darknessomi/musicbox](https://github.com/darknessomi/musicbox/tree/9c405f4bae2384d0410e63f8b816a707553d72d3) | `9c405f4b`, 2026-08-27 | MIT | Active independent direct real product. | Strong independent behavior/wire corroboration. |
| [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi/tree/b976e68cc3a068342a87f921f9bf086a611aaea0) | `b976e68c`, 2024-02-28 | No license file found at inspected HEAD | Historical upstream baseline. | Historical evidence only. |
| [feeluown/feeluown-netease](https://github.com/feeluown/feeluown-netease/tree/baa02dcf1acdebbcb11cf5d05117133614538c8a) | `baa02dcf`, 2026-04-14 | No top-level license located in this audit | Active real-product direct plugin. Some older mutation routes differ from current API families. | Evidence-only; disagreements stay explicit. |

Enhanced plus ncm-api-rs count as one wire family. go-musicfox is not counted
twice with its vendored client. MusicBox is the clearest current independent
real-product corroborator.

### KuGou Music

| Source | Exact current commit / activity | License | Role and independence | Fura boundary |
| --- | --- | --- | --- | --- |
| [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi/tree/b624d645a5213829882f06088e148bd43b1b1fa3) | `b624d645`, 2026-09-22 | MIT | Active direct API family. | Direct evidence; independent Fura implementation. |
| [Linsxyx/KugouMusic.NET](https://github.com/Linsxyx/KugouMusic.NET/tree/0cf0db0752bc87e1bd9990b7ea7330a9965f3604) | `0cf0db07`, 2026-09-20 | MIT | Active independent direct client. | Main independent cross-check. |
| [MoeKoeMusic/MoeKoeMusic](https://github.com/MoeKoeMusic/MoeKoeMusic/tree/b974ff5c5183be902ff92519f4fd905ec6cae93e) | `b974ff5c`, 2026-09-22 | GPL-2.0 | Real product whose API submodule points to MakcRe. | Product evidence; same wire family as MakcRe. |
| [EchoMusic](https://github.com/hoowhoami/EchoMusic/tree/81ec320cd14be6c4cc6972d7b3236b6c27e8ec0d) | `81ec320c`, 2026-09-24 | GPL-3.0 | Real product whose server submodule is MakcRe. | Product evidence; same wire family as MakcRe. |
| [lyswhut/lx-music-desktop](https://github.com/lyswhut/lx-music-desktop/tree/ad95d5091c9ed689fa72b5e5c849df65f5a679ce) | `ad95d509`, 2026-09-19 | Apache-2.0 | Active product; some media behavior is supplied by external API/plugins. | Product UX evidence does not prove a first-party direct wire. |
| [listen1/listen1_chrome_extension](https://github.com/listen1/listen1_chrome_extension/tree/3f24efa045125875a609dcb0f3f3f0be4edb8b37) | `3f24efa0`, 2025-06-17 | MIT | Older secondary implementation. | Secondary corroboration only. |
| [musicdl](https://github.com/CharlesPikachu/musicdl/tree/e5c3bd51b518642c24027921e63f482865809b61) | `e5c3bd51`, 2026-09-23 | PolyForm Noncommercial-1.0.0 | Current downloader/product evidence, not an automatically reusable provider. | Evidence-only. |
| [bamboostrip/KugouMusic.rs](https://github.com/bamboostrip/KugouMusic.rs/tree/b7a251d3aabb44e26382e8fca01bc7d70b34fc39) | `b7a251d3`, 2026-09-02 | No declared license | States it was inspired by KugouMusic.NET. | Not an independent vote; no code reuse. |

MakcRe + MoeKoe + EchoMusic are one wire family plus two real-product
integrations, not three protocol votes. KugouMusic.rs also does not add an
independent vote. MakcRe and KugouMusic.NET are the two primary independent
families.

## QQ_PARITY_MATRIX

| Capability | Third-party current reality | Fura current state | Classification / action |
| --- | --- | --- | --- |
| Track/Artist/Album/Playlist Search | Present across active direct clients. Search profiles differ. | All four typed searches use strict provider-owned identity and paging. | `CURRENT_FURA_PRIMARY`; `NO_CHANGE` to profile without a bounded Human-authorized comparison. |
| Suggestions / autocomplete | Dedicated SmartBox/complete routes exist in current clients. | UI currently derives a bounded title list from the first Track Search page. | `THIRD_PARTY_CORROBORATED`, `PRODUCT_DECISION_REQUIRED`; a provider-neutral contract is plausible only with equivalent NetEase semantics. |
| Hot search | Current direct clients/products expose hot keys. | No provider-neutral hot-search product surface. | `THIRD_PARTY_CORROBORATED`, `PRODUCT_DECISION_REQUIRED`. |
| Track/Album/Artist/Playlist details | Broad current corroboration. | Typed strict details and paged rows are primary. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| Rankings / recommendations / releases / related | Broad current corroboration. | Implemented with exact provider semantics; unsupported categories are omitted. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| Standard/High/Lossless media | Current direct clients use dispatch plus VKey families. | Exact provider-owned resolver reports actual quality and rejection. | `CURRENT_FURA_PRIMARY`. Anonymous CDN dispatch now has server-TTL cache; VKey remains uncached. |
| Source batching / prefetch | Multi-item VKey shapes exist. Safe batch maximum, correlation, partial failure and credential replacement are not sufficiently proved. | One Track VKey request at a time. | `HUMAN_LIVE_REQUIRED`; no queue prefetch change. Future candidate is current + next 2–3 only. |
| Lyrics | Current sources support line/QRC word timing and auxiliary tracks. | Shared `SynchronizedLyrics` includes QRC word timing. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| MV / comments | Corroborated current routes. | Exact Track-owned implementations. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| QR/auth/restore | Current products cover QR/session lifecycle with profile differences. | QQ/WeChat QR and desktop Quick Login retain one credential/session owner. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| Liked/Favorite collections and recent history | Current products commonly use collection snapshots. | Account-generation session cache absorbs loaded pages; route switches are zero-read. | `CURRENT_FURA_PRIMARY`; architecture already matches the audit goal. |
| Like/unlike, Album favorite, playlist Track mutation/create/delete | Current evidence and Fura's accepted implementation overlap. | Desired-state writes, typed unknown outcome and reconciliation are implemented where advertised. | `CURRENT_FURA_PRIMARY`; no retry or ownership expansion. |
| External Playlist save/unsave | L-1124 exposes `PlaylistFavWrite` (`FavPlaylist`/`CancelFavPlaylist`), but no second independent current wire family supplies equivalent detail. | Not advertised or wired. | `EVIDENCE_BLOCKED`; remain hidden. |
| Radar / cloud Recent Plays | QQ-specific product surfaces exist. | Implemented only for QQ and capability-gated. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |

## NETEASE_PARITY_MATRIX

| Capability | Third-party current reality | Fura current state | Classification / action |
| --- | --- | --- | --- |
| Track/Artist/Album/Playlist Search | Stable across current independent clients. | All four typed searches use strict identity and pagination. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| Suggestions / hot search | Active direct/product sources expose them. | Same bounded Track Search-derived suggestion UX as QQ; no hot-search surface. | `THIRD_PARTY_CORROBORATED`, `PRODUCT_DECISION_REQUIRED`. |
| Catalog/details/rankings/releases/related | Broadly corroborated. | Typed exact-owner operations are primary. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| Standard/Higher/Exhigh/Lossless | Current clients request multiple named levels and receive an actual level. | Domain supports Low/Standard/High/Lossless and truthfully reports server downgrade. | `CURRENT_FURA_PRIMARY`. |
| HiRes/Jyeffect/Sky/Vivid/Jymaster | Current API families expose additional levels whose entitlement, encoding and product meaning differ. | Not represented in `AudioQuality`. | `PRODUCT_DECISION_REQUIRED`; do not collapse into Lossless or expand the enum in this audit. |
| Line lyrics + translation + romanization | Stable legacy route. | Existing shared synchronized lyrics. | `CURRENT_FURA_COMPAT`. |
| `/api/song/lyric/v1` + YRC words | Enhanced and independently go-musicfox use the v1 EAPI route and YRC tracks; MusicBox also uses v1 but does not parse word timing. | Now maps bounded absolute YRC words, translation and romanization into shared `SynchronizedLyrics`; malformed YRC atomically falls back to valid LRC. | `EVIDENCE_READY_PROTOCOL_CHANGE`, implemented offline. |
| Auth/session restore | Active products cover QR/cookie flows. | Official-Web-only login boundary plus isolated credential owner. | `CURRENT_FURA_PRIMARY`; existing Human/platform gates remain. |
| Liked-state read | Current direct clients use `/api/song/like/get` as an account snapshot; `/api/song/like/check` was found only in Enhanced plus its derivative port. | Fura now wires `like/get` into a generation-scoped, single-flight account membership index while retaining the real Liked Playlist solely for display order. | `CURRENT_FURA_PRIMARY`; no per-Track network check. |
| Track like/unlike and owned playlist create/Track mutation | Corroborated and already implemented with desired-state semantics. | Production operations are capability-gated and reconciled. | `CURRENT_FURA_PRIMARY`. |
| Album favorite/unfavorite | Enhanced and independent go-musicfox agree on `/api/album/sub` and `/api/album/unsub`. | Client-level one-attempt foundation and deterministic tests now exist; no Provider/Bridge/UI advertisement. | `OFFLINE_FOUNDATION_ONLY`, `HUMAN_LIVE_REQUIRED`. |
| Artist follow/unfollow | Enhanced and independent go-musicfox agree on `/api/artist/sub` and `/api/artist/unsub`. | Client-level one-attempt foundation and tests now exist; not advertised. | `OFFLINE_FOUNDATION_ONLY`, `HUMAN_LIVE_REQUIRED`. |
| Owned Playlist delete | Enhanced and independent go-musicfox agree on `/api/playlist/remove`; FeelUOwn retains an older conflicting `/playlist/delete`. | Client-level `/api/playlist/remove` foundation and tests exist; not advertised. | `OFFLINE_FOUNDATION_ONLY`; dedicated disposable-playlist write/read-back required. |
| External Playlist save/unsave | Enhanced's current EAPI/check-token shape and go-musicfox's WEAPI shape disagree materially. | Not implemented. | `EVIDENCE_BLOCKED`, `HUMAN_LIVE_REQUIRED`. |
| Personal FM | Stable current product capability and already part of Fura's accepted NetEase surface. | Existing provider-specific surface. | `CURRENT_FURA_PRIMARY`, `NO_CHANGE`. |
| Cloud music / podcast-DJ-voice / listening reports / style | Present in some current products/APIs. | Outside current product scope. | `PRODUCT_DECISION_REQUIRED`; gap audit only. |
| Cross-provider unblock/source substitution | Present in Enhanced-family tools. | Explicitly absent. | `REJECTED`: a NetEase Track must retain NetEase as media owner. |

## KUGOU_PARITY_MATRIX

| Capability | Third-party current reality | Fura current state | Classification / action |
| --- | --- | --- | --- |
| Track Search | Independent families and the closed live window support exact MixSongID-centered rows. | Strict Search exists with provider-private hash/Audioid context. | `CURRENT_FURA_PRIMARY` within Core; production UI still blocked. |
| Artist/Album/Playlist Search | Static sources expose candidates, but the closed live window returned business `20006` for unsigned variants. | Not implemented. | `EVIDENCE_BLOCKED`; no new live request budget. |
| Exact Track detail | Static sources plus the closed window explained envelope and status variations. | Strict exact detail exists and correlates MixSongID/hash/Audioid/Album ID. | `CURRENT_FURA_PRIMARY` within Core. |
| Playlist/Album/Artist details and Tracks | Modern static routes exist, but signing/session inputs or HTTPS-to-HTTP downgrade remain unresolved. | Not advertised. | `EVIDENCE_BLOCKED`; offline candidate only after two safe current HTTPS families agree. |
| Rankings | Independent sources and closed-window behavior support inventory plus row paging. | Strict Ranking inventory/Tracks exist. | `CURRENT_FURA_PRIMARY` within Core. |
| Recommendations / new releases / related / comments / MV | Third-party products expose varying routes and proxy/plugin behavior. Exact safe direct contracts are not yet independently proved. | Not implemented. | `EVIDENCE_BLOCKED` or `PRODUCT_DECISION_REQUIRED` by surface. |
| Line LRC | Closed-window exact-hash route was bounded and compatible. | Line-timed LRC exists. | `CURRENT_FURA_PRIMARY` within Core. |
| KRC word timing | MakcRe proves `fmt=krc` download and envelope decoding. KugouMusic.NET alone supplies the independently inspected `[line]` + `<word>` structural parser and language metadata mapping. | No KRC parser or advertised word timing. | `EVIDENCE_BLOCKED`: two independent structural implementations do not yet agree, so the requested evidence bar is not met. |
| Standard/high/lossless media | MakcRe and KugouMusic.NET overlap on `/v2/get_res_privilege/lite`, `/v5/url`, `/v6/priv_url`, identity/quality and account entitlement fields. Their signing/device assumptions remain unsafe or unclassified; inspected v6 code also uses an HTTP tracker. | No resolver. | `HUMAN_DECISION_REQUIRED`; this continues to block production UI. |
| Authentication/library/mutations/recent | Product sources exist, but no independently accepted public/auth boundary is established. | Unsupported and unadvertised. | `EVIDENCE_BLOCKED`; no fake authentication or cross-provider fallback. |

### KuGou media field boundary

The minimal static overlap is exact provider identity (`hash` plus
MixSongID/album-audio context), requested quality, entitlement response and the
three route families above. It does not make all request fields acceptable:

- `PUBLIC/STABLE_PROTOCOL`: exact Track identity, requested quality, response
  quality/format and public protocol fields independently demonstrated as such.
- `SESSION_OWNED`: token, user ID, VIP token/state and any future server-issued
  anonymous/account session field.
- `LOCALLY_RANDOM_NONSECRET`: timestamp or nonce only after evidence proves it
  is neither stable tracking identity nor app impersonation.
- `DEVICE_IDENTITY_UNCLASSIFIED`: generated/fallback `dfid`, `mid`, `uuid` and
  install identifiers. These cannot enter production without a Human decision.
- `PRIVATE/IMPERSONATION_RISK`: embedded official-app salts, private signing
  secrets, package/certificate identity and fabricated hardware identity.
- `RISK_CONTROL`: SSA/security-verification flags, CAPTCHA behavior, WebGL or
  device simulation, identity rotation and risk-control evasion.

Only the first three classes could become acceptable, and only with independent
evidence. Fura will not extract app secrets, forge package/device identity,
rotate `dfid`, bypass CAPTCHA/SSA, decrypt protected audio, or substitute a QQ
or NetEase source.

## CROSS_PROVIDER_ARCHITECTURE_FINDINGS

### Reuse justified by domain semantics

- All lyrics end at `SynchronizedLyrics` with bounded `LyricLine` and timed
  segments. QQ QRC, NetEase YRC and any future KuGou KRC remain separate
  parsers; the UI model is shared.
- Flutter asks a session-scoped membership owner for `stateFor(track)`. A
  provider may satisfy that with a targeted authoritative read or an
  authoritative collection snapshot. Widgets do not own the network cache.
- A confirmed mutation applies a precise session-cache delta. An unknown
  outcome invalidates/reconciles only the target. Account generation change
  invalidates the entire provider-owned view.
- Media routing shares only provider-owned `TrackId`, requested quality,
  reported actual quality and typed availability. A generic short-lived source
  cache is justified only when TTL and credential-generation semantics really
  match; the current QQ dispatch cache remains provider-local.
- Single-flight is valuable for duplicate idempotent reads, but not for
  mutation retries. One in-flight account snapshot or dispatch request may be
  shared; a write remains one attempt with explicit unknown outcome.

### Cache ownership taxonomy

- **A — public protocol cache:** Provider/process scoped, anonymous state such
  as QQ CDN dispatch. It survives login/logout and stores no identity,
  credential, VKey or final media URL.
- **B — account snapshot cache:** liked IDs, favorite Albums and recent
  history. It belongs to one explicit account generation; old-generation work
  returns `Replaced` and cannot publish into its successor.
- **C — short-lived authorization cache:** future VKey/media sources may use
  this class only with both account-generation ownership and hard server TTL.
  It is not implemented by this workstream.
- **D — presentation cache:** Flutter-owned derived display state. It is not a
  protocol authority and cannot be used to infer membership completeness.

The lifecycle invariants differ, so no universal `CacheManager` was added.

### Capability truth and diagnostics

Rust tests now compare the complete ordered descriptor capability set for QQ,
NetEase and KuGou Core, and compile-time trait bounds prove the mutation
contracts advertised by the two production Providers. Flutter no longer uses
its product-policy constants alone: startup intersects them with the descriptor
from the running Core. Missing capabilities fail closed; extra unaccepted Core
capabilities cannot open a control. KuGou's descriptor remains Core evidence
only, with a regression proving it is absent from `BuiltInProvider::ALL`.

`FURA_PROVIDER_DIAGNOSTIC=1` enables local-only coarse request-cost lines for
membership, mutation, QQ dispatch and QQ VKey phases. The vocabulary contains
only Provider, operation, phase, cache hit/miss, single-flight join, request
count, typed outcome and generation current/replaced. It has no identity,
query, title, URL, VKey, cookie, token, credential, account-content or response
body field and has no telemetry transport.

### Similar-looking concerns that must not be shared

- Opaque IDs, search profiles, signature material, cookies, device/session
  identifiers, CDN/VKey/media contracts and entitlement meanings stay inside
  their Provider.
- Audio quality labels do not have guaranteed cross-provider equivalence.
- An external search/unblock match cannot translate identity or media ownership.
- QQ playlist save, NetEase playlist subscribe and future KuGou collection
  operations are separate write contracts, not one inferred endpoint shape.
- QRC, YRC and KRC syntax are separate protocol decoders even though they map
  into one domain model.

## SAFE_CHANGES_IMPLEMENTED

### QQ provider-owned CDN dispatch cache

`provider-qqmusic` now keeps one memory-only, single-flight anonymous CDN
dispatch entry. Freshness is the strict earliest of server `expiration`,
`refreshTime` and `cacheTime`; failure is never cached. Account credentials,
VKeys, final media URLs and Track identity are not stored, logged or persisted.

Deterministic instrumentation proves:

- 10 sequential Track resolutions: before 10 dispatch + 10 VKey = 20 requests;
  after 1 dispatch + 10 VKey = 11 requests while the server TTL is fresh;
- two concurrent cold resolutions share one dispatch but retain two exact VKey
  requests;
- the earliest server TTL (1,800 seconds in the fixture) triggers refresh;
- a failed dispatch is retried by the next caller rather than poisoning cache.

This is a 45% reduction for the measured ten-Track resolver path. It is not a
claim about Home/Search/Playlist traffic, and it does not implement VKey batch
or queue prefetch.

## PROTOCOL_CHANGES_IMPLEMENTED

### NetEase account membership snapshot

The previously unused client `/api/song/like/get` read is now the production
membership source. One generation-scoped, memory-only snapshot serves all
Hearts. Concurrent cold reads join one request, a confirmed Like/Unlike applies
one target delta, and an indeterminate write marks the snapshot for an atomic
replacement without exposing stale work to a replacement account. The actual
Liked Playlist `trackIds` remains the ordered presentation source; membership
completeness is independent from successful `TrackSummary` rendering.

Offset zero is not an implicit refresh signal. Flutter sends one explicit,
provider-neutral membership-refresh marker only for manual refresh or the
targeted reconciliation of an unknown write. A confirmed write may refresh
the visible collection row, but keeps the account membership snapshot and its
delta; ordinary route entry also remains a zero-membership-read operation.

Flutter recognizes a complete exact Provider snapshot separately from the
presentation cursor, so a 1,032-ID membership set can establish positive and
negative Heart state after one membership page rather than forcing all display
pages to render. QQ retains its existing paged continuation because each QQ
wire page contributes only that page's authoritative identities.

### NetEase lyric v1 / YRC

NetEase lyrics now use the current EAPI `/api/song/lyric/v1` request shape and
map absolute bounded YRC word timings, translation and romanization into the
existing shared model. Envelope, text and count bounds remain strict. A
malformed/overlapping/out-of-line/overflowing YRC track cannot corrupt valid
canonical lyrics: the whole word track is rejected and a valid LRC track is
used instead. Protocol text stays redacted from diagnostics.

The implementation is independently derived from observed route and syntax
behavior; no third-party module was copied or translated.

## OFFLINE_FOUNDATIONS

The NetEase client now has one-attempt, typed foundations for:

- Album favorite/unfavorite: `/api/album/sub` and `/api/album/unsub`;
- Artist follow/unfollow: `/api/artist/sub` and `/api/artist/unsub`;
- owned Playlist delete: `/api/playlist/remove`.

Deterministic tests verify exact method routing, authenticated request
ownership, invalid-input zero-request behavior and preservation of unknown
outcomes. Nothing was added to Provider descriptors, Bridge, Flutter or UI.
These operations are not advertised and require a separately authorized real
account gate. Playlist deletion may only be tested with a newly created,
disposable test Playlist followed by an authoritative read-back.

KuGou KRC is not an offline implementation in this revision because the two
independent current families did not both establish the word-level grammar.

## HUMAN_GATES

- QQ Search mobile-vs-desktop comparison: propose one serial request per
  profile, no retry/rotation, redacted output, immediate stop on risk response.
- QQ VKey batch/prefetch: prove maximum safe batch, item correlation,
  partial/global failure, expiry, account replacement and rejection semantics
  before considering current + next 2–3 Queue Tracks.
- NetEase Album/Artist/delete writes: dedicated disposable entities, one
  request, authoritative read-back, no automatic retry.
- NetEase external Playlist save: resolve current EAPI-vs-WEAPI disagreement
  before any write.
- KuGou: no live gate is proposed in this audit. The 40/40 window is closed;
  any later request needs a new Human-approved purpose and budget.

## PRODUCT_DECISIONS

- Whether dedicated provider-neutral Suggestions and Hot Search improve the
  product enough to justify new Core/Bridge/Flutter surfaces.
- Whether HiRes, immersive/effect and master quality labels deserve distinct
  cross-provider domain values and UX rather than remaining unavailable.
- Whether NetEase cloud music, podcast/DJ/voice, listening reports and style
  surfaces belong in Fura.
- Whether any KuGou locally generated non-secret identifier is acceptable; no
  device/install-shaped identifier is accepted by default.

## REJECTED_PATTERNS

- NetEase unblock or cross-provider media substitution.
- Treating forks, ports, submodules or products consuming the same server as
  independent protocol votes.
- Whole-playlist source prefetch, persistent media URL/VKey caches, mutation
  retry, response-body logging or query/identity logging.
- KuGou HTTP downgrade, official-app secret extraction, app/package identity
  impersonation, fabricated hardware identity, risk-control evasion or proxy
  sidecars.
- Provider-specific lyric, membership or Queue models in Flutter.

## NETWORK_COST_BEFORE_AFTER

Only the QQ media resolver has a deterministic before/after measurement in
this audit. The broader requested cold boot, Home, Search, Playlist, 20 route
switches and Like/Unlike profile requires authenticated runtime instrumentation
and was not executed without a Human live gate. Existing session ownership
makes ordinary QQ/NetEase route switches zero-read for completed membership
snapshots; that is covered by the deterministic Home → Search → Album →
Playlist → Recent → Expanded Player → Home controller sequence rather than a
service traffic capture. NetEase cold membership now uses one
`/api/song/like/get` snapshot per account generation and never fans out into
one `/song/like/check` request per Heart.

No provider service traffic was generated by this audit, and no query, title,
identity, URL, cookie, token or response body was retained.

## Answers to the Human's fifteen questions

1. **QQ repeated requests:** the proven waste was anonymous CDN dispatch once
   per Track resolution; it is now one single-flight request per strict server
   TTL. Liked/Favorite route-level rescans were already removed by the existing
   account-session membership owner. No other traffic reduction is claimed
   without instrumentation.
2. **QQ cache/batch/prefetch:** CDN dispatch is safely memory-cached using the
   earliest server TTL. VKey batching is protocol-plausible but not yet safe
   enough to ship; URL/VKey persistence and full-playlist prefetch are rejected.
3. **QQ Search profile/UX:** no current profile clearly supersedes Fura's
   Desktop path, especially given code-2001 risk evidence. Dedicated
   Suggestions/Hot Search are worthwhile product candidates, but need a
   provider-neutral decision and bounded live comparison.
4. **QQ external Playlist save:** it remains blocked. Current L-1124 detail is
   one wire family, not the independent second corroborator required for a
   destructive account write.
5. **NetEase formerly blocked mutations:** Album favorite, Artist follow and
   owned Playlist `/remove` now have substantially stronger current evidence
   and offline client foundations. They remain behind real-account Human gates.
   External Playlist save remains blocked by incompatible request families.
6. **NetEase direct liked-state:** no per-Track request should replace the
   current `/song/like/get` account snapshot. It is now one session-level
   authoritative index; `/song/like/check` lacks independent corroboration and
   would add route-switch traffic.
7. **NetEase lyric/v1:** yes, current independent evidence supports bounded YRC
   word timing. It is implemented with translation/romanization and atomic LRC
   fallback.
8. **NetEase HiRes/Master:** not in this audit. Their entitlement, format and
   product meanings are not equivalent enough to silently map into the current
   enum; expansion is a product decision.
9. **KuGou KRC:** not yet. Download/decode and one full structural parser do
   not meet the requested two-independent-implementation grammar threshold.
10. **KuGou modern Catalog:** static candidates exist, but no independently
    proved safe unsigned HTTPS contract clears the closed-window failures and
    HTTP downgrade. They remain blocked/offline candidates.
11. **KuGou media minimum overlap:** the three privilege/URL route families,
    exact provider identity, quality selection and entitlement state. That
    overlap does not validate signing, device identity or transport safety.
12. **KuGou accepted fields:** public exact identity/quality, server-owned
    session fields and a proved non-tracking nonce may be acceptable. Generated
    `dfid`/`mid`/`uuid`, hardware/install identity, app secrets, certificate or
    package impersonation, SSA/CAPTCHA/risk-control inputs must not enter Fura.
13. **Reusable architecture:** the synchronized-lyrics domain, provider-owned
    session membership semantics, typed mutation outcome/reconciliation,
    single-flight idempotent reads and exact provider-based media routing.
14. **Never share:** opaque identity translation, cookies, signatures, device
    identity, Search profiles, media entitlement/quality assumptions, lyric
    wire parsers and cross-provider media fallback.
15. **User-visible savings:** the implemented QQ cache removes 9 of 20 resolver
    requests in the ten-Track fixture. Existing account-session membership
    indexes keep route switching at zero network reads. NetEase YRC improves
    lyric precision; the mutation foundations intentionally provide no claimed
    user benefit until Human live acceptance and production composition.

## Validation

- `cargo fmt --all -- --check`: passed.
- `cargo test --locked --workspace --all-targets`: passed; explicitly ignored
  live/Human tests stayed ignored and generated no Provider traffic.
- Strict `-D warnings` Clippy passed for every affected production library
  target, including the Flutter Bridge. The changed NetEase membership,
  mutation-foundation and KuGou fixture tests also pass under normal locked
  workspace/all-target execution.
- The host toolchain is Arch `rustc 1.98.1`, Cargo 1.98.1 and Clippy 0.1.98;
  rustup is not installed. One combined strict all-target Clippy run is not
  green: it stops on pre-existing test-only `async fn` transport
  implementations across `qqmusic-client` and `provider-qqmusic` under the
  newer `unused_async_trait_impl` lint. Production-library Clippy passes; no
  global lint allow, unknown-lint suppression or out-of-scope fixture rewrite
  was introduced.
- Pinned `flutter_rust_bridge_codegen 2.13.0` regenerated the explicit
  membership-refresh API, and generated Rust was formatted afterward.
- `dart analyze --fatal-infos` passed through an ASCII temporary symlink to
  the same worktree. Direct analysis from the Chinese absolute path exits
  before diagnostics because Dart 3.13.1 truncates its LSP initialization
  frame. All 929 Flutter tests passed from the real worktree.
- `git diff --check`: passed.
- No service live probe, real-account mutation, Flutter production capability
  advertisement, commit or push was performed.
