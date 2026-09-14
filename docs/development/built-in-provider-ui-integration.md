# Built-in Provider UI integration

Date: 2026-09-12. Authority: HD-025. Execution:
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

QQ currently owns Radar, cloud Recent Plays and remote library mutations.
Those controls and destinations are absent for NetEase. Unsupported regional
choices are omitted rather than sent as speculative requests. A smaller Home
is valid when a Provider has fewer truthful slots.

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
| Lyrics | DONE | NetEase line timing and exact translation work without invented word timing. |
| Comments | DONE | Current Track Provider owns paged hot/newest reads. |
| MV | DONE | Current Track Provider owns exact associated-MV resolution. |
| Media resolution | HUMAN_REVIEW | Authenticated NetEase media now uses current interface3 EAPI desktop context; deterministic routing tests pass, but a real entitled Track must be replayed by the Human. |
| Queue | DONE | Mixed QQ/NetEase positions and same opaque IDs preserve exact next/previous routing. |
| Now Playing | DONE | Current Track identity, not Settings selection, owns playback-adjacent reads. |
| Provider switching races | DONE | Search, controller, QR and verification late work is suppressed/cancelled without sign-out; playback survives. |
| Capability hiding | DONE | NetEase Radar and cloud Recent Plays destinations are absent. |
| Unsupported mutations | DONE | No NetEase remote-write control or QQ write fallback is composed. Queue-local actions remain available. |
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
