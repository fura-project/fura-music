# Built-in Provider UI integration

Date: 2026-09-12; KuGou gate updated 2026-09-24. Authority: HD-025 plus the
2026-09-24 resumed KuGou workstream. Execution:
`AUTONOMOUS_DEVELOPMENT / MIXED`.

## Product semantics

Settings persists exactly one catalog/account presentation choice:
`qq-music` or `netease-cloud-music`. Missing and legacy settings select QQ
Music. A selection changes subsequent Home, Discover, Search, Library and
authentication work; it is not a sign-out and does not merge services.

The Queue is deliberately independent. Every queued Track keeps its original
provider-scoped opaque identity, so media, lyrics, comments, MV and related
reads route to the owning Provider even after Settings changes. No identity is
parsed or translated by Flutter, and no failed source is substituted from the
other service.

## KuGou production gate

The Core now contains a third provider-owned public read slice under
`kugou-music`: existing Track Search, exact Track detail, Rankings and
line-timed LRC. Its versioned opaque Track identity keeps `MixSongID` canonical
and hides the exact standard-hash/Audioid/duration/Album resolution context
inside `provider-kugou`. The public client remains direct Rust HTTPS; there is
no sidecar, runtime registry, QQ/NetEase credential reuse or cross-Provider
lookup.

KuGou is deliberately not a third `BuiltInProvider` or `AppMusicProvider` yet.
The 2026-09-24 anonymous evidence window exhausted its 40-request limit without
finding a standard playable source: legacy detail returned no URL and four
deterministic standard-source probes returned no candidate. Modern media routes
still combine signing with device/install-shaped inputs that are outside the
accepted safety boundary. Therefore:

`KUGOU_UI_PRODUCTION_GATE = BLOCKED_BY_MEDIA`

The ordinary Settings selector, bootstrap inventory, native media composition,
Bridge dispatch and Flutter dependencies remain exactly QQ Music plus NetEase
Cloud Music. This is not a browse-only KuGou product and no fake signed-out
authentication gateway is composed. When a standard resolver is independently
proved, the planned third-provider integration must still add static routing,
optional authentication semantics, public-only Home/Discover/Search capability
hiding, same-opaque-ID collision tests and mixed-Queue owner routing before UI
exposure.

## Credential and authentication boundary

QQ Music and NetEase Cloud Music use separate secure-storage keys, serialized
access and Rust session owners. Rejection cleanup may delete only the owning
Provider's stored credential. Startup restores only the selected Provider;
switching to another Provider activates its own lazy restore flow without
probing inactive accounts.

QQ retains desktop Quick Login plus QQ and WeChat QR where supported. NetEase
uses only its official website at the product boundary: the isolated Linux
system-browser flow imports the resulting bounded session after service
verification, while the Flutter gateway advertises neither internal QR nor SMS
login. Fura does not collect a password.

## Capability mapping

Both Providers supply typed Search, catalog details, rankings, public
recommendations, supported new releases, related Tracks, lyrics, comments, MV,
media and an authenticated library foundation. NetEase Daily Tracks and
Personal FM keep those names and do not impersonate QQ Daily 30 or Radar.

Flutter product policy is now intersected at startup with the exact capability
list returned by the running Rust Provider descriptor. A missing Core
capability therefore hides the corresponding action even if Flutter policy
would normally allow it, while an extra Core capability cannot opt a Provider
into a product surface that has not passed its product/Human gate. The typed
bootstrap remains exactly QQ Music and NetEase Cloud Music; KuGou Core is
tested separately and is not admitted by this truth check.

QQ owns Radar, Album favorite and Playlist deletion. Both production Providers
currently advertise Track Like, Recent History read, owned-Playlist Track
mutation and Playlist creation. NetEase Album favorite, Artist follow and
owned Playlist removal remain client-only offline foundations: their Core
descriptor does not advertise those operations, so Flutter cannot show them.
Unsupported regional choices are omitted rather than sent as speculative
requests. A smaller Home is valid when a Provider has fewer truthful slots.

## Membership and cache ownership

Track and Album membership are account-generation state owned above routes and
widgets. QQ continues its bounded liked/favorite collection scan and retains
the next raw offset; NetEase loads `/api/song/like/get` once as an unordered
account membership snapshot while the actual Liked Playlist remains the source
of presentation order. Concurrent Hearts join the same load. Confirmed writes
apply only the target delta, unknown outcomes mark only the target unknown and
request an atomic replacement, and definitive failures preserve the previous
authoritative state. Manual refresh keeps the old snapshot until the exact
replacement succeeds. Logout, credential/account replacement and Provider
replacement are the only immediate invalidation boundaries.

Loading presentation offset zero is not cache invalidation. Manual Track
membership refresh crosses one explicit Bridge boundary; confirmed-mutation
row refresh and route re-entry retain the account snapshot and perform zero
additional membership reads.

The cache taxonomy is intentionally semantic rather than one generic manager:

- **Public protocol cache:** anonymous Provider/process state such as QQ CDN
  dispatch; logout does not clear it.
- **Account snapshot cache:** liked IDs, favorite Albums and recent history;
  owned by one authenticated generation and discarded on replacement.
- **Short-lived authorization cache:** QQ and NetEase now own sixteen-entry
  memory-only resolution LRUs keyed by exact Provider TrackId, preferred quality
  and session generation, with hard server TTL and conservative remaining
  validity. The small value in provider-api owns no credentials or IO; each
  Provider owns its single-flight lock and generation check. Logout/credential
  replacement invalidates old sources. No URL is written to disk.
- **Presentation cache:** Flutter-derived display/artwork state; owned only by
  the UI layer and never treated as protocol authority.

Playback packet memory is a separate source-lifetime NativePlayer cache, serving
seek/replay without a new resolve/open. Repeat-one follows the Rust completion
action, not the Settings-selected Provider. No cross-session byte storage,
automatic credential rotation, third KuGou inventory or public browse-only
Provider is implied by these caches. Current continuation gates are recorded in
the [2026-10-06 audit](../research/provider-playback-session-audit-2026-10-06.md).

Development request-cost tracing is opt-in with
`FURA_PROVIDER_DIAGNOSTIC=1`. It reports only Provider, operation category,
phase, cache hit/miss, single-flight join, request count, typed outcome and
generation current/replaced. Its API has no Track/Album/Playlist ID, query,
title, URL, VKey, cookie, token, credential or response-body field, and it does
not send telemetry.

## Switch lifecycle

Changing selection increments a presentation generation, cancels operations
owned by the old catalog/account context where possible, resets nested detail
navigation to the new Provider root and suppresses every late old-generation
completion. Playback work already attached to a queued provider-owned Track is
not part of that reset.

## Evidence boundary

Offline fixtures and Widget tests can prove routing, isolation, persistence,
rollback, stale-result suppression, capability hiding and Queue retention.
They cannot prove real personalized content, authenticated media entitlement,
target secure-storage behavior or visual acceptance. The Human confirmed the
Linux external-browser login and a signed-in Library on 2026-09-14; the media
compatibility repair still requires a new Human playback check.

## Machine checkpoint

The implementation reuses the existing page tree and keeps the Queue owner
outside the provider-scoped controller lifecycle. Shared Bridge operations take
or derive an exact Provider ID; private QQ and NetEase protocol types remain in
their Providers. Search, recommendation, release, ranking, library, detail,
related, lyrics, comments and MV paths dispatch only to that owner. The two
credential vault keys and rejection-cleanup paths are tested independently.

The NetEase authentication adapter reuses the existing login controller but is
marked official-Web-only. The generic start action and the only visible login
button enter the same official website operation. Switching while website login
or stored-credential verification is active invalidates that UI work.
Cancellation is not sign-out: a pending NetEase credential remains available
for an explicit retry, and inactive Provider state is not cleared.

Final local machine evidence on 2026-09-12:

- pinned `flutter_rust_bridge_codegen 2.13.0` completed; no generated API file
  was deleted or left orphaned;
- Rust format, workspace tests, all-target tests and strict Clippy passed: 535
  passed, 0 failed, 20 explicit live/Human tests ignored;
- 237 Dart files passed the format gate, `dart analyze` reported no issues and
  all 527 Flutter tests passed;
- Linux Release built successfully;
- Android ARM64 Release built successfully as a 43,768,152-byte APK;
- desktop/compact Settings, compact signed-out NetEase, desktop NetEase Search
  and desktop synthetic signed-in NetEase Library frames were inspected for
  overflow, provider-copy leakage and unsupported controls. Their aesthetic
  acceptance remains Human-owned.

## Remaining Work Audit

| Area | Classification | Evidence boundary |
| --- | --- | --- |
| Settings Provider selection | DONE | Material 3 single selection is searchable, keyboard/touch reachable and persisted. |
| Provider settings migration | DONE | v1/v2 default to QQ; QQ, NetEase, unknown v3, rollback and rapid serialized writes are tested. |
| Provider bootstrap inventory | DONE | Typed bootstrap contains exactly QQ, NetEase and QQ default. |
| QQ credential vault | DONE | Existing key and restore compatibility retained. |
| NetEase credential vault | DONE | Independent key, serialized access and isolated cleanup tested. |
| QQ auth | DONE | Existing desktop Quick Login and QQ/WeChat QR composition retained. |
| NetEase auth | HUMAN_ACCEPTED_LINUX | Human confirmed isolated system-browser login and a signed-in Library; other platforms plus restart/sign-out isolation retain their own gates. |
| Search x4 | DONE | Selected gateway bundle routes all four categories without aggregation. |
| Home | DONE | Anonymous/authenticated slots are capability- and Provider-truthful in synthetic tests. |
| Discover | DONE | Supported releases/rankings/playlists reuse the existing page; Radar is capability-gated. |
| Library | DONE | Provider-scoped account/playlists/favorite collections are wired and stale state is replaced. |
| Liked | DONE | Existing paged page consumes the owning typed liked-playlist identity. |
| Playlist Detail | DONE | Exact entity Provider ID drives paged loading. |
| Album | DONE | Details and Tracks route by the Album owner. |
| Artist | DONE | Tracks and Albums route by the Artist owner. |
| Rankings | DONE | Groups and raw-cursor Track pages route by selected/entity Provider. |
| New Songs | DONE | Only categories with exact Provider semantics are shown. |
| New Albums | DONE | Only regions with exact Provider semantics are shown. |
| Related Tracks | DONE | Seed Track Provider owns the request. |
| Lyrics | DONE | NetEase uses current lyric/v1, mapping bounded YRC word timing plus exact translation/romanization into the shared model; malformed YRC falls back atomically to valid LRC. QQ retains QRC word timing. |
| Comments | DONE | Current Track Provider owns paged hot/newest reads. |
| MV | DONE | Current Track Provider owns exact associated-MV resolution. |
| Media resolution | HUMAN_REVIEW | Authenticated NetEase media now uses current interface3 EAPI desktop context; deterministic routing tests pass, but a real entitled Track must be replayed by the Human. |
| Queue | DONE | Mixed QQ/NetEase positions and same opaque IDs preserve exact next/previous routing. |
| Now Playing | DONE | Current Track identity, not Settings selection, owns playback-adjacent reads. |
| Provider switching races | DONE | Search, controller, QR and verification late work is suppressed/cancelled without sign-out; playback survives. |
| Capability hiding | DONE | NetEase Radar and cloud Recent Plays destinations are absent. |
| Unsupported mutations | DONE | No unaccepted remote-write control or cross-Provider fallback is composed. NetEase Album favorite, Artist follow and owned Playlist remove now have client-only offline foundations, but remain absent from Provider descriptors, Bridge and UI until an authorized real-account gate. Queue-local actions remain available. |
| Signed-out QQ | DONE | Existing public Shell remains available. |
| Signed-out NetEase | DONE | Public Home/Discover/Search remain; account-only content is absent and CTA names NetEase. |
| Synthetic signed-in NetEase | DONE | Account, Library, Daily Tracks and Personal FM composition is covered. |
| FRB | DONE | Pinned generation and generated-source consistency passed. |
| Rust tests | DONE | 535 passed, 0 failed, 20 ignored. |
| Flutter tests | DONE | 527 passed. |
| Linux build | DONE | Release bundle produced locally. |
| Android build | DONE | ARM64 Release APK produced locally. |
| Visual synthetic renders | HUMAN_EVIDENCE_REQUIRED | Required frames exist and passed machine inspection; aesthetics are not self-accepted. |
| Human NetEase real account | PARTIAL_HUMAN_EVIDENCE | Linux web login and signed-in Library are observed; favorites/personalized reads, restart/sign-out isolation and authenticated media are not all accepted. |
| Human current pending platform reviews | HUMAN_EVIDENCE_REQUIRED | Existing Android system-media and credential-transfer Go/No-Go gates remain unchanged. |

There is no `REMAINING_AUTONOMOUS_WORK` item in this bounded HD-025 scope.
Real-account evidence must not be inferred from fixtures, builds or generated
bindings.
