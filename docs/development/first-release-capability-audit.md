# First-Release Capability Audit — 2026-08-27

## Scope and evidence vocabulary

This audit records the reusable capability foundation needed by the already
authorized QQ Music-first product. Visual redesign is paused. A capability is
`VERIFIED` only for the evidence named here; offline tests do not prove current
live QQ behavior, and a successful build does not prove a target runtime.

Safety classes are `anonymous read`, `authenticated read`, `remote mutation`,
and `platform-local`. First-release decisions are `Required`, `Later`,
`Human decision`, and `Out of scope`.

## A — Account and authentication

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| WeChat QR sign-in lifecycle | A normal user can establish an account session. | `VERIFIED`: client/provider/Bridge/controller tests cover create, scan, confirm, expiry, refusal, timeout, cancellation, retry budget, and replacement; the maintainer observed a successful scan. | No core layer. | authenticated read | Required | One bounded QR session reaches authenticated or an exact terminal state without leaking account material. |
| Credential persistence, restore, and server verification | Restart does not silently lose or falsely trust a session. | `VERIFIED`: versioned Rust credential document, platform vault adapter, server verification, rejection/replacement rules, and Linux/Android disposable vault integrations exist; the maintainer observed restore. | Apple/Windows runtime evidence remains absent. | platform-local + authenticated read | Required | Stored material becomes authenticated only after QQ acceptance; transient failures preserve it and explicit rejection clears it at the platform edge. |
| Sign-out and account replacement | A user can safely end or replace a session. | `VERIFIED`: late login/verification/library results cannot cross replacement; sign-out orders core and vault cleanup and exposes cleanup failure. | No core layer. | authenticated read | Required | Active core state is cleared, stale operations cannot promote, and vault failure remains visible/retryable. |
| Signed-in account summary | A user can confirm which QQ Music account is active before using personal data or mutations. | `IMPLEMENTED`: two current independent implementations agree on nested `info.nick` / `info.logo`, including one measured real-session shape; synthetic client fixtures plus Domain, Provider, cancellable Bridge, and Dart-gateway tests cover bounded mapping, redacted diagnostics, rejection, cancellation, vault cleanup, and exact account replacement. | Later presentation integration and optional maintainer-operated live observation; neither blocks the reusable foundation. | authenticated read | Required | A bounded display name and optional avatar are mapped from current evidence, redacted in diagnostics, and remain tied to exact credential generation. |
| Additional login methods | Some users may not use WeChat. | `OUT_OF_SCOPE`: no demonstrated first-release blocker; one maintained login path already works. | All layers. | authenticated read | Later | Requires evidence that WeChat QR alone materially blocks target users. |

## B — Home recommendation data

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| Public recommended playlists | Supplies a truthful general discovery shelf. | `VERIFIED`: bounded anonymous client/provider/Bridge/controller paging and offline fixtures exist. It is not personalized Daily Recommendations. | Broad live compatibility is not established. | anonymous read | Required | Current public playlist pages map to provider-neutral summaries with bounded paging and exact failures. |
| Daily Recommendations | Gives a listener a small personalized daily starting point. | `MISSING`: Home currently relabels no data as daily; no truthful typed capability exists. | Bounded protocol/product discovery, then Client through Bridge. | authenticated read | Required | A currently evidenced QQ daily recommendation result has stable identity, bounded Tracks/playlists, account replacement, cancellation, and offline fixtures. |
| Treasure Playlist Library | Offers a distinctive QQ playlist-discovery surface rather than the user's own library. | `MISSING`: personal playlists are not semantically equivalent and no verified source exists. | Product/protocol discovery and all reusable data layers. | anonymous or authenticated read, evidence-dependent | Required | Discovery identifies a stable QQ playlist collection whose semantics actually match; otherwise it becomes `EVIDENCE_BLOCKED`. |
| Popular Programs | Could expose a QQ-native editorial program surface. | `HUMAN_DECISION_REQUIRED`: no capability exists, and a spoken-audio root could conflict with the explicit podcast non-goal. | Product-boundary decision before implementation; protocol discovery may remain bounded. | read, evidence-dependent | Human decision | Proceed only if the maintainer confirms a bounded music-product role that does not create a podcast/general-media client. |
| Listening-based song recommendations | Helps users resume music related to established listening. | `MISSING`: neither of the two requested Home sections has a verified capability; Radar is a distinct QQ-native surface and is not silently substituted. | Protocol semantics, Domain/Provider/Bridge, account replacement/cancellation. | authenticated read | Required | One evidenced reusable recommendation contract can supply truthful bounded Track sets; a second section must have distinct semantics or reuse the same capability transparently rather than inventing variety. |

## C — Personal Library

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| User playlists and liked songs | Users can reach their primary saved music. | `VERIFIED`: owned/favorite aggregation, liked-songs routing, playlist detail paging, cancellation and account replacement have offline coverage; the maintainer observed the real playlist list. | M1 real playback observation remains separate; TD-005 bounds favorite aggregation at 1,000 rows. | authenticated read | Required | Complete bounded collection and details load without silent truncation or cross-account results. |
| Favorite Albums and Artists | Users can browse saved catalog entities. | `VERIFIED`: authenticated paged Client → Provider → Bridge → Dart paths and retained pages have offline regressions. | Broad live-account compatibility is not established. | authenticated read | Required | Typed pages preserve opaque identity, continuation, credential rejection, and replacement. |
| Like/unlike Track | A listener can keep or remove the current Track in the built-in liked-song collection. | `IMPLEMENTED`: three current implementations agree on the playlist-detail write protocol, and one has an authenticated reversible roundtrip. This repository has exact offline Client, Provider, cancellable Bridge, Dart-gateway, credential-rejection, and account-replacement coverage only. | Minimal later verification control, refresh integration, and maintainer-operated live acceptance. | remote mutation | Required | One desired liked/not-liked state maps from opaque Track identity; invalid input is rejected before transport; uncertain network/response/replacement/cancellation outcomes require refresh and are never reported as confirmed. |
| Add/remove Track from owned playlist | Users can organize saved music beyond the built-in liked collection. | `MISSING`: the underlying protocol is independently evidenced, but no provider-neutral target-playlist mutation contract or refresh wiring exists. | Extend the bounded Client/Provider/Bridge contract to validated owned playlists; minimal verification control later. | remote mutation | Required | Only an owned opaque playlist target is accepted; one Track add/remove has offline request, failure, cancellation, replacement, and refresh-consistency coverage; live acceptance remains maintainer-operated. |
| Create/rename/delete playlist | Users can manage their own playlist containers. | `MISSING`: no mutation implementation exists. | Protocol evidence and every reusable layer; destructive confirmation remains Flutter-owned later. | remote mutation | Required | Typed create/edit/delete results and refresh consistency are covered offline; destructive live acceptance is maintainer-operated only. |
| Favorite/unfavorite Album or Artist | Browsing can update the same saved collections shown by Library. | `MISSING`: read paths exist but mutation paths do not. | Protocol evidence and Client through Bridge. | remote mutation | Required | Exact entity identity, idempotent outcome, account replacement, and subsequent collection refresh are covered offline; live acceptance is maintainer-operated. |

## D — Playback and media

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| Standard media resolution and foreground playback | A selected QQ Track can produce sound. | `EVIDENCE_BLOCKED`: standard MP3 resolution, redacted expiring sources, local/loopback Linux playback, and corrected protocol tests exist; the real authenticated QQ playback observation is still pending. | Maintainer-operated M1 observation only unless it reproduces a defect. | authenticated read + platform-local | Required | Ordinary QQ Track plays through the current foreground owner; coarse live result is recorded without URI, identity, or credential data. |
| Track availability and failure taxonomy | Users are not given invented VIP/region/copyright explanations. | `VERIFIED`: unavailable, credential rejection, network/service, invalid response, core unavailable, and replacement remain distinct through Provider/Bridge/Dart. | More specific entitlement reasons lack evidence. | authenticated read | Required | Coarse states remain truthful end to end; finer reason is added only with repeatable evidence. |
| Audio quality selection and fallback | Users can choose an appropriate stream without making every failure terminal. | `IMPLEMENTED`: three current implementations agree on M500 standard MP3 and M800 high MP3; Client, Provider, Bridge, Dart gateway, and settings tests cover exact requests, actual returned quality, High-only unavailable fallback, redaction, cancellation, and account replacement. A bounded no-account gate accepts both schemas. | Settings UI remains deferred; authenticated account entitlement/playback observation remains maintainer-operated. | authenticated read + platform-local preference | Required | Standard or High can be requested; High falls back only from an unavailable item to Standard; the actual quality is reported and no VIP state is guessed. |
| Queue, previous/next, shuffle, repeat, removal, and completion | Daily listening remains predictable across a session. | `VERIFIED`: Rust positional queue owns order/repeat/completion; Bridge and one Dart owner have domain, adapter, controller, and Widget regressions. | Cross-session persistence is not authorized. | platform-local | Required | Duplicates and mutations retain positional identity; completion and manual traversal follow documented mode semantics. |
| Seek, volume, source replacement, and failure recovery | Playback remains controllable when a source changes or fails. | `VERIFIED` for offline/local behavior: controller generation, stale suppression, seek/volume, retry, stop, and Queue-selected replacement are tested. | Real QQ source behavior remains inside the M1 observation. | authenticated read + platform-local | Required | Late resolution/player events cannot replace a newer Track and failure retains a recoverable current Queue state. |
| Synchronized and word-timed lyrics | The defining lyric experience follows playback. | `EVIDENCE_BLOCKED`: QRC decryption/parsing/alignment and position-driven presentation are well covered offline; a credential-free live lyric gate exists; the authenticated playback-to-lyrics observation remains pending. | Maintainer-operated M1 observation. | authenticated read | Required | Synchronized lines advance during real playback and word timing appears when the source supplies it; only coarse outcome is retained. |

## E — Catalog and Search

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| Track, Artist, Album, and Playlist Search | Users can find the principal QQ catalog entities. | `VERIFIED`: four typed paged paths, feature-specific parsing, cancellation/stale suppression, error/retry behavior, retained results, and Widget tests exist. | Broad live catalog coverage is not claimed. | anonymous read | Required | Each type validates its own identity and paging and returns to retained state without raw QQ models crossing the Bridge. |
| Playlist, Album, and Artist browsing/context | Search and discovery lead to playable catalog detail. | `VERIFIED`: paged Tracks, Album metadata, Artist Albums, and Track → Album/Artist routes exist with exact return-state tests. | Artist biography and other secondary metadata are not required. | anonymous/authenticated read | Required | Validated opaque identities reach typed detail and playable Track summaries without protocol logic in Dart. |
| Rankings, Radar, new Songs/Albums, recommendations | Users have QQ-native discovery beyond Search. | `VERIFIED` for bounded contracts and offline fixtures; Radar is authenticated and generation-checked. | Broad live freshness/quality is not claimed. | anonymous read; Radar authenticated read | Required | Existing named surfaces retain their distinct semantics, paging, and failure states. |
| Search history, hot words, suggestions, users, MV Search | Convenience or broader media discovery. | `OUT_OF_SCOPE`: no first-release evidence outweighs complexity/product expansion. | All layers. | read, evidence-dependent | Later or Out of scope | Requires a separate demonstrated user need and accepted Roadmap authority. |

## F — App Settings

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| Typed persistent settings foundation | Stable preferences survive restart and later UI can bind without inventing storage rules. | `VERIFIED`: a version-2 typed document stores system/light/dark plus standard/high playback preference through the official async `shared_preferences` API; startup wiring, defaults, version-1 migration, malformed/future handling, read/write/reset, storage failure, and a disposable Linux native round trip pass. | Other target runtimes remain covered by the Platform row. The final Settings UI is deliberately deferred. | platform-local | Required | Versioned typed settings persist only implemented preferences with validated defaults and migration; malformed/future data fails safely; no Settings page is added. |
| Playback-quality preference | A chosen quality can become the default request. | `IMPLEMENTED`: standard is the compatibility-preserving default, High is the only higher option, version-1 documents migrate to Standard, and startup injects the loaded preference into the typed media gateway. | Final Settings UI and maintainer-operated authenticated behavior observation remain deferred. | platform-local | Required after quality support | Persist only Standard/High, default and migrate to Standard, and pass the loaded preference into Rust-owned negotiation without inventing another playback owner. |
| Lyric translation/romanization preferences | Users can hide/show available auxiliary lines. | `OUT_OF_SCOPE` for now: current Domain aligns auxiliary text but does not prove stable translation versus romanization classification. | Evidence and typed lyric metadata before a setting. | platform-local | Later | Add only after the lyric source can truthfully distinguish the controlled content. |

## G — Platform integration

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| In-app keyboard/media shortcuts | Desktop listeners can control playback without pointer travel while the app is focused. | `VERIFIED`: hardware media-key intents and Ctrl shortcuts route to the single Queue/controller owner with focus regressions. | OS-global media session is separate. | platform-local | Required | Focused app shortcuts activate the same guarded actions as visible controls. |
| System media session, lock-screen controls, and background playback | Playback remains controllable outside the foreground app. | `HUMAN_DECISION_REQUIRED`: the selected engine and architecture explicitly cover foreground playback only; no background service/session exists. | Product requirement, lifecycle architecture, platform implementations, target evidence. | platform-local | Human decision | Maintainer decides whether this is a first-release criterion before a service/media-session dependency or lifecycle redesign is introduced. |
| Secure storage runtimes | Sessions survive restart on supported targets. | `ENVIRONMENT_BLOCKED`: Linux and Android x64 disposable round trips pass; iOS, macOS, and Windows are unrun (TD-004). | Target environments. | platform-local | Required per distributed target | Each target passes the isolated non-account write/read/delete contract with cleanup before distribution. |
| Foreground audio/video runtimes | Local decoding and lifecycle controls work on the actual target. | `ENVIRONMENT_BLOCKED`: packaged Linux audio/video paths and bounded Android emulator packaging/runtime evidence exist; physical Android and Apple/Windows remain unverified. | Target environments and real-device evidence. | platform-local | Required per distributed target | Exact target passes bounded local playback/lifecycle tests; real QQ and hardware claims remain separate. |

## H — Comments, MV, and related Track data

| Capability | User value | State and evidence | Missing layers | Safety | First-release decision | Acceptance boundary |
| --- | --- | --- | --- | --- | --- | --- |
| Read-only hot/latest comments | Users can read the main social context without turning the client into a social platform. | `VERIFIED`: opaque text identity, author/content redaction, time, praise count, hot/latest separation, raw-row pagination, blank deleted-row filtering, offline tests, and a default-ignored credential-free live gate pass. | Reply summaries are not modeled. | anonymous read | Required | Current endpoint returns bounded hot/latest pages with exact continuation and no retained user content in evidence. |
| Comment replies and mutations | Richer conversation or posting/liking. | `OUT_OF_SCOPE`: neither is required for the bounded read-only product role. | All layers. | read or remote mutation | Later / Out of scope | Requires separate product authority; no autonomous social mutation. |
| Track-associated MV metadata/source | A Track can open its exact QQ MV when one exists. | `VERIFIED`: association, metadata, artwork, duration, quality/source choice, none/unavailable/failure states, offline tests, and a default-ignored live gate pass. Local Linux video lifecycle is separately verified. | Remote-source playback and other target runtimes are not proven. | anonymous read + platform-local | Required | Exact associated MV maps to one redacted provider-neutral object; music/video ownership remains singular and unavailable is truthful. |
| Generic video feed/search/download | A separate video product. | `OUT_OF_SCOPE` by product constitution and M5 boundary. | All layers. | read/mutation | Out of scope | Requires a new human product decision and must not be inferred from Track MV support. |

## Ranked immediate candidates

1. **Owned-playlist Track add/remove** — the next smallest reversible library
   write and the closest extension of the now-bounded liked-Track protocol. It
   must reject favorite/catalog playlist targets and retain unknown-outcome
   semantics; real-account acceptance remains maintainer-operated.
2. **Home recommendation capability discovery** — needed by the accepted Home
   composition, but must establish each section's semantics rather than reuse
   public recommendations or personal playlists under misleading names. Popular
   Programs remains product-authority-sensitive.

The Settings, signed-in account-summary, two-quality media, and liked-Track
mutation foundations are complete within their stated platform/live-evidence
boundaries. The next selected task is bounded add/remove for one Track and one
validated owned playlist; it may not execute the maintainer's stored account or
fabricate mutation success.
