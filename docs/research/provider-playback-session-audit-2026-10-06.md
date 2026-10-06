# Provider, playback and session audit — 2026-10-06

Status: playback/cache and profile extraction implemented; refresh foundations
are offline candidates, not production automatic continuation. Overall task is
not complete. Physical-device and real-session gates remain open.

## Source baseline and authority

- HEAD and local `origin/main`: `ee8dc24697bd506155d3e16f72c4a36209efd347`.
- Initial `git status --short` and `git diff --stat`: empty.
- Preserve the committed identity/privacy and Provider parity work. No commit,
  push, reset, restore or clean is authorized by this task.
- Architecture remains Flutter → typed FRB 2.13.0 → Rust Domain/Provider →
  provider-specific direct HTTPS client. No sidecar or raw JSON boundary.
- Sequence: audit → playback/cache → profiles → QQ → NetEase → KuGou →
  refresh/persistence integration → soak. A blocked capability does not grant
  permission to weaken security or silently advertise an incomplete Provider.

## Pre-change code facts at the baseline HEAD

| Area | Current implementation | Consequence |
| --- | --- | --- |
| Queue completion | `music-domain/src/playback_queue.rs::complete_current` returns bool; repeat-one and advancing both return true | Cannot express replay versus opening another source. |
| Flutter completion | `QueuePlaybackController::_completeCurrent` calls `TrackPlaybackController.playTrack` for true | Repeat-one stops, re-resolves and reopens; not source reuse. |
| Track loading | `playTrack` stops the previous session before beginning resolution | Normal replacement semantics are appropriate, but not EOF replay. |
| MediaKit lifetime | One engine-lifetime Player; source sessions own subscriptions/focus; terminal engine dispose destroys Player | Preserve this ownership and MV isolation. |
| MediaKit serialization | `_operationTail` waits on native Futures without a deadline; terminal dispose also waits | One stuck operation can wedge subsequent controls/cleanup. |
| MediaKit EOF focus | Completed event deactivates focus | Source replay must not acquire/release focus each cycle. Terminal/stop cleanup must still release it. |
| Playback byte cache | No Fura-owned explicit cache property policy in the adapter | Inspect pinned NativePlayer/libmpv before configuring it. |
| Resolution cache | QQ has a server-TTL, single-flight CDN dispatch cache; final VKey URLs are uncached; NetEase final sources uncached | Dispatch cache is not Track/session-scoped resolution cache. |
| Persistent byte cache | None | Do not confuse URL caching with media-object persistence. |

### QQ

`qqmusic-client::media_resolution` has modern `UrlGetVkey` and
desktop-compatible `CgiGetVkey`. The Provider tries compatibility only for
the documented `104003` route gap, not as credential/risk rotation. It
reports actual quality and server validity. `CredentialSessionSecrets`
retains access token, refresh token/key, open/union/encrypted account material;
there is no implemented `refresh_credential` operation. The Provider retains
authenticated/pending/expired states and compares exact credential candidates
around awaits. Explicit rejection still clears that candidate; no explicit
monotonic media-session generation exists yet. CDN dispatch is memory-only,
bounded by the earliest server TTL. Do not replace this already-correct cache.

These media requests are currently unsigned. Authenticated/signed-in does not
mean cryptographically signed; no new signing profile is implied by this audit.

### NetEase

WEAPI and EAPI exist. Authenticated media uses `interface3` EAPI. The current
credential media context includes `os=pc`, `appver=8.0.0`, `versioncode=140`,
`buildver=1623435496`, resolution, request nonce and `MUSIC_U`/`__csrf`;
several device fields contain literal `undefined`. These are existing wire
values, not permission to fabricate replacement fingerprints. `AuthOwner`
owns active/pending credentials, a watch generation and single-flight liked
membership; old generation work returns Replaced. There is no token-refresh
operation. Explicit authenticated rejection clears the owning generation.

### KuGou

Public Track Search, exact Track detail, rankings and line-timed LRC exist.
Provider-private v1 context preserves MixSongID, standard hash and Audioid.
Broader Search/Catalog capabilities remain blocked, not implemented merely
because the descriptor contains coarse Search/Catalog. Standard media remains
`BLOCKED_BY_MEDIA`; there is no resolver, BuiltInProvider, media routing,
bootstrap or Settings third option. The previous 40/40 live window is closed.
This task authorizes evidence research, not an unbounded new service window or
official secret/device/risk impersonation. Authenticated profile remains a
research candidate until ordinary session and install identity are classified.

## Persistence and session ownership

QQ and NetEase have separate process-owned Providers and platform vault keys.
Rust validates/serializes opaque versioned credentials. Flutter's
`SerializedCredentialVault` serializes a single secure-storage key; mutable
FFI buffers are cleared after the write. It is not a transaction between Rust
installation and durable storage, and there is no refresh persistence handshake.
The new refresh path must not install rotated credentials and leave an old
vault silently usable after restart. No stored real credential may be read by
the agent for testing. Fixtures must be synthetic.

## Evidence and acceptance boundaries

Existing auth/media/credential-storage, playback-stack and parity research is
historical evidence, not proof of fresh service or physical-device acceptance.
Profiles must first preserve existing request shapes with deterministic tests.
Refresh needs pinned independent route/envelope/rotation/rejection evidence;
real account refresh/media and mobile network/background/BT tests remain Human
gates. Mutation writes must never be replayed on ambiguous failure.

Field classification: PUBLIC_PROTOCOL, REQUEST_NONCE, SESSION_OWNED,
SERVER_ISSUED_INSTALL, INSTALL_SCOPED, DEVICE_UNCLASSIFIED, PRIVATE_APP_SECRET,
PACKAGE_ATTESTATION, RISK_CONTROL, CONTENT_PROTECTION. Unclassified device
inputs stay absent/unchanged; private secrets, attestation spoofing, risk
bypass and protected-content unlocking remain prohibited.

## Execution record

The changes below are an uncommitted working-tree diff on the same HEAD.
Implementation proceeded sequentially. No Provider descriptor or visible
Provider inventory was expanded. A request-shape test is not live evidence;
a loopback synthetic-source test is not authenticated remote media or physical
device proof.

### Playback and cache

- Domain completion now returns `PlaybackCompletionAction`: repeat-one is
  `ReplayCurrent`, advancing/wrapping is `PlayCurrent`, terminal/empty is
  `None`. FRB and the Dart gateway carry and validate that action. The existing
  playback-request flag remains compatibility metadata for other Queue actions,
  not a Flutter repeat-mode decision.
- Replay retains the session and executes seek(0) → play. It does not stop,
  resolve, reopen, dispose or reacquire focus. EOF focus is released for terminal
  completion, a failed completion gateway, stop or terminal disposal. Next-Track
  replacement retains its existing stop/resolve/open path.
- NativePlayer's public `setProperty` configures a source-lifetime packet cache:
  `cache=yes`, `cache-on-disk=no`, `demuxer-seekable-cache=yes`, forward/back
  demuxer limits of 64 MiB each, `demuxer-readahead-secs=600`, `keep-open=yes`.
  The six-hundred-second horizon remains bounded by those byte limits; these
  are an engineering memory/seek policy, not a Provider URL TTL. See the
  [mpv option semantics](https://mpv.io/manual/stable/) and the pinned
  `media_kit` 1.2.6 NativePlayer implementation in the local dependency cache.
  Disk caching was not enabled: mpv disk-cache metadata limits are not a hard
  media-byte disk quota. This is explicitly not an offline/download cache.
- Serialized native operations have open/control deadlines of 15/5 seconds,
  player generation and cycle guards, and a coarse timeout diagnostic. These
  are recoverability budgets, not service protocol constants. Pending native
  Futures are not cancellable; late results cannot install a stale session.
  The next explicit load may perform one single-flight retirement/rebuild per
  engine lifetime. Failed retirement prevents constructing a replacement.
  `NativePlayer.dispose(synchronized:false)` avoids waiting for the same held
  operation lock. The SDK schedules native handle destruction five seconds
  after disposal; one active replacement is bounded, but immediate zero
  native-handle overlap is not claimed. No indefinite rebuild/retry was added.
- `MediaResolutionCache` is a bounded sixteen-entry in-memory LRU value, not a
  new runtime. Keys contain full Provider-owned TrackId, preferred quality and
  session generation; cached values preserve actual quality/format. Expiry
  begins before the request and never exceeds `valid_for_seconds`. Remaining
  TTL is floored, and less-than-one-second entries miss. No URL is serialized
  or logged. Providers retain ownership of credentials, locks and invalidation.
- QQ now has a monotonic session generation, including identical credential
  re-login, plus generation-bearing snapshots for authenticated read completion.
  Old rejections cannot clear the new session. NetEase retains its existing
  generation/watch owner. Both resolution paths single-flight concurrent reads
  and miss across logout/account replacement; QQ public CDN dispatch retains
  its existing independent server-TTL cache.

Measured deterministic request costs:

| Workload | Before | After | Boundary |
| --- | --- | --- | --- |
| QQ ten distinct sequential Tracks | 1 CDN dispatch + 10 VKey | unchanged | Existing CDN cache preserved; no batching/prefetch. |
| QQ ten resolutions of one Track, same quality/generation | 1 dispatch + 10 VKey | 1 dispatch + 1 VKey | Only within real source TTL. |
| NetEase ten resolutions of one Track | 10 media requests | 1 media request | Preferred quality and generation isolated. |
| Ten concurrent same-Track resolutions | Duplicate source work | One source resolution per Provider | Synthetic blocked transport fixtures, not ten refreshes. |
| Repeat-one EOF | Resolve/open each time | Zero additional resolve/open | Source retained. |

Persistent media cache v1 is **BLOCKED / NOT IMPLEMENTED**. The current
NativePlayer seam does not supply a verified complete-object, single-download
handoff with hard disk quota and integrity/atomic publication semantics. An
independent downloader would create a second fetch path; using mpv disk-cache
files as durable media would incorrectly equate cached packets with validated
media objects. No localhost proxy, signed-URL filename, URL persistence or
unbounded disk cache was introduced. Future work must prove a bounded handoff
and account/entitlement ownership before LRU/atomic-final storage is enabled.

### Explicit Provider-private profiles, unchanged wire strategy

`qqmusic-client/profile.rs`, `netease-client/profile.rs` and
`kugou-client/profile.rs` own their respective constants/headers. There is no
shared mega-profile or runtime registry. Transports perform HTTP/TLS/bounds;
they no longer silently invent Provider UA policy. Specific existing QR/SMS
header overrides remain explicit protocol exceptions.

| QQ capability | Current owner / preset | Session / signing boundary |
| --- | --- | --- |
| Search x4 | Desktop, ct=19; Track Search cv="1859" | Existing Desktop Primary, no Android/risk rotation. |
| Catalog | Web public ct=24/cv=0 and existing Desktop/legacy capability presets | Exact capability shapes retained, not one interchangeable comm. |
| Recommendations | Web public/library presets; Desktop compatibility where already implemented | Anonymous versus authenticated retained. |
| Authentication | Web modern ct="11"/cv=v=13020508; separate QQ ptlogin/WeChat browser overrides | No new fake official device/package. |
| Account | Web modern | Credential remains client/Provider-private. |
| Library | Web library cv=v=4747474 and existing ct presets | Generation-bearing authenticated snapshots. |
| Lyrics | Web modern | Existing QRC transport/format retained. |
| Media | Modern ct="11" UrlGetVkey; Desktop ct=19/cv=0/platform="20" CgiGetVkey | Currently unsigned. Compatibility only for the existing proven 104003 gap. |
| Comments | Web legacy H5 GET | No new authenticated claim. |
| MV | Existing Web public musicu presets | Track-owned exact association retained. |

| NetEase capability | Current owner / preset | Boundary |
| --- | --- | --- |
| Search x4 | DesktopEapi, cloudsearch/pc | Existing EAPI body/query-type/pagination unchanged. |
| Catalog/Library | WebWeapi where previously used | Existing crypto and request payload unchanged. |
| Lyrics v1 | DesktopEapi | Existing YRC/LRC/auxiliary mapping retained. |
| Authenticated media | DesktopEapi, interface3 base override | Original os/appver/versioncode/buildver/request nonce/MUSIC_U context. |
| QR | WebWeapi with existing browser UA | No new browser-cookie harvesting. |
| SMS | Existing explicitly authorized mobile EAPI exception | Existing device/context behavior preserved, not extrapolated to Desktop. |
| Refresh candidate | One-shot WebWeapi | Not promoted; WEAPI/EAPI and refresh-Cookie compatibility unresolved. |

The current Desktop `undefined` device fields were moved without changing
their values. The existing SMS-generated context is not silently removed or
extended by this extraction. KuGou has only an active Public profile; an unused
Authenticated variant was not invented to suggest a working login/media path.

Golden checks freeze QQ Search's complete envelope and effective headers,
QQ preset values/types, NetEase's complete fixed-nonce Desktop media
Cookie/header object and headers, and KuGou public headers. Existing endpoint
fixtures continue checking routes, body fields, quality, auth, bounds and
failure semantics. A new snapshot for every endpoint has **not** been produced;
do not claim exhaustive per-endpoint pre/post golden coverage from the profile
constant test alone.

### Current source provenance and refresh/media findings

Read-only public source snapshots were inspected, not executed. Observation
does not grant code-copy permission. GPL/no-declared-license sources were used
only for route/field/behavior evidence, never code translation. Dates below are
the checked HEAD dates, not claims of service compatibility or latest meaningful
protocol activity.

| Source | Exact commit checked | Provenance and finding |
| --- | --- | --- |
| [L-1124/QQMusicApi](https://github.com/L-1124/QQMusicApi/tree/27861e51432ea6b6e88dc35c4e8c8e239c0339e8) | 27861e51432ea6b6e88dc35c4e8c8e239c0339e8 (2026-10-05) | MIT, direct client; LoginServer Login/loginMode=2, loginType-dependent material. Current overall profile is Android-shaped. |
| [YAQMC/qm-api-rs](https://github.com/YAQMC/qm-api-rs/tree/75f6e4d392f6d3e64608fb48e2480fb0087009e3) | 75f6e4d392f6d3e64608fb48e2480fb0087009e3 (2026-09-16) | GPL-3.0-or-later; explicitly based on L-1124, not another independent wire vote. |
| [yakult-green-tea/qq-music-api](https://github.com/yakult-green-tea/qq-music-api/tree/e1be9638ec14f562ffb718586d5654884b319bbf) | e1be9638ec14f562ffb718586d5654884b319bbf (2026-10-05) | MIT, Rain120-derived family; full WeChat refresh params corroborate L-1124, but outer request uses Android session policy. |
| [simple-music](https://github.com/Yyyangshenghao/simple-music/tree/69e4921e9bdc36181ec19f52229af2fea55212eb) | 69e4921e9bdc36181ec19f52229af2fea55212eb (2026-10-03) | GPL-3.0 real product/direct QQ wire; CgiGetVkey and playback-key semantics, no independent LoginServer refresh found. Its cookie key fallback is not permission to substitute refresh material as music_key. |
| [amtoaer/lyrune](https://github.com/amtoaer/lyrune/tree/1320e5dc5f55ce531937a9a05082b35b422a95f5) | 1320e5dc5f55ce531937a9a05082b35b422a95f5 (2026-09-27) | Product license is unknown; its API crate identifies the MIT AstronW/netease-qq-music-api upstream. README credits earlier QQ references, so neither wrapper nor vendored crate is automatically an independent vote. QQ refresh has Desktop ct=19/cv=2201 and a different param subset. NetEase uses EAPI refresh and explicitly requires MUSIC_R_U. No bypass/decrypt implementation is adopted. |
| [go-musicfox/netease-music](https://github.com/go-musicfox/netease-music/tree/912f2cf2b8bf772c804c6cd4b4f31f11773c7b93) | 912f2cf2b8bf772c804c6cd4b4f31f11773c7b93 (2026-04-26) | MIT direct Go client with historical NCM API lineage. WEAPI login/token/refresh uses a shared CookieJar; this does not prove MUSIC_U/__csrf-only refresh. Request-strategy/unblock mechanisms are rejected. |
| [HyPlayer.NeteaseProvider](https://github.com/HyPlayer/HyPlayer.NeteaseProvider/tree/c11cd1278ed0b3a232242eded7e6d14d1c9f8683) | c11cd1278ed0b3a232242eded7e6d14d1c9f8683 (2026-08-18) | MIT in LICENCE (README's LICENSE link is misnamed). Static EAPI/device-field evidence only; no independent token-refresh contract found. |
| [darknessomi/musicbox](https://github.com/darknessomi/musicbox/tree/9c405f4bae2384d0410e63f8b816a707553d72d3) | 9c405f4bae2384d0410e63f8b816a707553d72d3 (2026-08-27) | MIT real direct client; media URL refresh is not login-token refresh. No second minimal-credential refresh proof. |
| [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi/tree/da5ccfd9304c043085a2fd18e94ebc5c315044ab) | da5ccfd9304c043085a2fd18e94ebc5c315044ab (2026-10-02) | MIT wire family; registration/device/risk inputs and v5 url are not an accepted ordinary public-media contract. MoeKoe/EchoMusic do not add independent votes. |
| [Linsxyx/KugouMusic.NET](https://github.com/Linsxyx/KugouMusic.NET/tree/2a9cedd912257c8097b0b2c19140733269bf8394) | 2a9cedd912257c8097b0b2c19140733269bf8394 (2026-09-25) | MIT independent direct client; RegisterClient obtains server-issued dfid, but registration inputs/device API origin remain unclassified. Server-issued output alone does not make fabricated inputs safe. |

Open Orpheus public product information did not yield an independently pinned
refresh wire implementation; it is not counted as corroboration. No KuGou
service request was sent; its previous 40/40 live window remains closed. No
real QQ/NetEase account credential was read or tested.

Field decisions:

| Field/family | Classification | Current decision |
| --- | --- | --- |
| ct/cv/platform/appver/os/Referer/UA | PUBLIC_PROTOCOL | Preserve established per-capability values, do not rotate profiles on risk. |
| NetEase requestId, local request nonce | REQUEST_NONCE | Generate only the already-evidenced nonce; never treat as hardware identity. |
| QQ music_key/access/refresh/open/union material; NetEase MUSIC_U/__csrf | SESSION_OWNED | Rust-owned, redacted, only opaque vault bytes cross FFI. |
| NetEase MUSIC_R_U | SESSION_OWNED candidate | Evidence suggests dedicated refresh material; not absorbed into the stored schema without accepted minimal contract/rotation proof. |
| KuGou register response dfid | SERVER_ISSUED_INSTALL candidate | Output provenance observed, full ordinary registration/media gate not satisfied. |
| KuGou mid/uuid and registration hardware-shaped inputs | INSTALL_SCOPED candidate / DEVICE_UNCLASSIFIED | No fabricated device, persistence or production media. |
| Official package/certificate/private signing key | PACKAGE_ATTESTATION / PRIVATE_APP_SECRET | Prohibited. |
| SSA/CAPTCHA/verification | RISK_CONTROL | Stop capability/probe, never evade or rotate. |
| Protected audio, QMC/MFLAC, VIP bypass | CONTENT_PROTECTION | No unlock/decrypt/cross-Provider source. |

### Refresh foundations versus production continuation

QQ now has an explicit one-shot `refresh_credential` Client candidate for
WeChat's complete corroborated material set. It bounds requests/responses,
refuses unsupported login types/incomplete rotation/account changes and returns
coarse failures without retry. It does not install the new credential. The
outer Web-compatible profile still requires evidence; implementing an Android
identity/signature just to refresh is not permitted. QQ loginType=2 is not
extrapolated from one family.

NetEase has an explicit one-shot WEAPI Client candidate. It checks the existing
business envelope before merging only MUSIC_U/__csrf, rejects conflicting,
foreign-domain, malformed, revoked and oversized known cookies, and preserves
the input on failure. Unknown cookies are ignored, not persisted. Current
evidence for EAPI+MUSIC_R_U means the minimal existing credential cannot be
called long-term refreshable. Unknown security codes are not guessed into a
logout outcome. No browser CookieJar or install fingerprint was added.

The following production requirements are **NOT IMPLEMENTED**, rather than
merely untested: refresh coordinator/single-flight refresh, near-expiry/startup/
resume scheduling, Refreshing/Offline/Reauthentication/Verification states,
refresh generation install, read refresh-once/retry-once, typed write-refresh
outcome, vault rotation handshake/recovery and restart-after-rotation. Existing
Provider behavior on a definitive owning CredentialRejected remains in place;
the P0 self-healing login goal is not yet met. Ten concurrent resolution tests
must not be cited as ten concurrent refresh tests.

Required next persistence contract, not implemented code: the Provider stages
a validated same-account candidate at a generation reservation; latest session
is re-read under the refresh single-flight lock; durable secure-vault candidate
write/ack must precede committing the new in-memory generation. Logout/account
replacement wins over a late acknowledgement. A journal/recovery state must
prevent a restart from accepting an invalidated rotated token when durable
publication fails. Failure preserves a coarse stale/unavailable state rather
than claiming both the old token and new memory state are current. No best-effort
install-B/write-B path was added to the current single-key adapter.

Candidate Human gate: maintainer operates a disposable QQ WeChat/NetEase session,
at most three requests per Provider (one refresh, one account verification,
one media verification), one attempt each, no write replay, no body/Cookie/URL
retention. Stop on 429/security/secondary verification/account disagreement.
First verify the minimum NetEase refresh-Cookie requirement; do not probe several
profiles until one happens to work. The agent has asked for this bounded gate
but has not received authorization or accessed stored credentials.

KuGou remains `KUGOU_UI_PRODUCTION_GATE = BLOCKED_BY_MEDIA`: normal login →
classified server/session/install identity → entitlement → clear HTTPS Standard
source is not proved within the permitted boundary. Public Core remains intact;
no BuiltInProvider, BuiltInMediaSources, bootstrap/Bridge or Settings third
option was added.

### Validation and unfulfilled acceptance

Verified so far in this task:

- Domain/Bridge typed completion tests, Provider TTL/generation/LRU/routing and
  ten-read concurrency regressions, QQ same-credential stale-read rejection,
  request-profile fixtures and synthetic client refresh foundations pass.
- The full locked Rust workspace/all-target test suite passed; live/Human tests
  stay ignored. A final post-change rerun is recorded separately below.
- Strict affected production-library Clippy passes on this host's Rust/Clippy
  1.98.1. Strict all-target checks for Domain/API/NetEase/KuGou pass. Full
  all-target Clippy is not green on pre-existing QQ test transport
  `unused_async_trait_impl` diagnostics; no global lint suppression was added.
- Pinned FRB 2.13.0 generation succeeded. Dart analysis and the full Flutter
  unit/widget suite passed (933 before the final additional control-stall test).
- Real Linux playback integration passed MP3/M4A/FLAC rollback adapter checks
  and MediaKit checks. The enlarged MediaKit integration completed 100 source
  replacements and 100 pause/resume operations with one active engine Player.
  RSS/threads at replacement counts 0/10/20/50/100 were 430/463/567/597/529 MiB
  and 62/65/62/59/59. This is one synthetic host observation, not a leak-proof
  bound or background/device soak. Its 100 EOF replays advanced position and
  generated **zero additional HTTP fixture requests**.
- Queue's exact 100-play-cycle checkpoint is one initial play plus 99 replays,
  with one resolution/open and no stop; a further 100th completion/replay is
  also exercised. This states the counting convention instead of claiming 100
  EOF events mathematically equal 99 replay actions.
- Real Linux MV MP4 decode/pause/seek/resume and default-request-D Linux Fura
  MPRIS session-bus registration/property checks passed. MV remains a separate
  disposable Player; it was not used to play music or own the Queue.

Not executed: physical Android/iOS/Windows/macOS audio/network/background/lock/
Bluetooth/resume cycles, twenty real foreground/background cycles, real service
refresh/account/media, secure-vault rotation/restart, KuGou login/media, or fresh
GitHub CI. Waydroid is installed but session is stopped and no physical ADB
device is available; no new emulator/runtime installation or data reset occurred.
The refresh hard-acceptance matrix is pending implementation, not passing.

No commit, push, reset, restore, clean, release, credential import or account
write was performed. UI layouts and existing platform packaging are unchanged.

### Final local checks at this checkpoint

- `git ls-remote origin refs/heads/main` still returns
  `ee8dc24697bd506155d3e16f72c4a36209efd347`; HEAD and local origin/main agree.
- System `rustc 1.98.1`, `clippy 0.1.98` (Arch packages), no rustup. No toolchain
  policy, CI baseline or dependency version was changed.
- `cargo fmt --all -- --check`: passed.
- Final `cargo test --locked --workspace --all-targets`: passed, exit 0.
  Default ignored real-service/Human tests were not invoked.
- `cargo clippy --locked --workspace --lib -- -D warnings`: passed, exit 0.
- Strict all-target Clippy for music-domain, provider-api, netease-client,
  provider-netease, kugou-client and provider-kugou: passed, exit 0.
- Final `cargo clippy --locked --workspace --all-targets -- -D warnings`:
  **failed**, exit 101, only the old async-without-await QQ test transport
  implementations (36 qqmusic-client unit-test, 1 live fixture, 9 Provider
  fixtures). HEAD source inspection confirms these were already present.
  New refresh fake transports use ready Futures. No suppressions or unrelated
  fixture rewrite was added. Two new doc-markdown findings were fixed before
  these final checks.
- Dart format: 292 files, zero changes. `dart analyze`: no issues. Final full
  `flutter test`: **934 passed**, exit 0, including the added native-control
  stall/bounded-rebuild regression. No Flutter layout production file changed.
- `flutter test integration_test/playback_engine_test.dart -d linux`: passed;
  the enlarged `--plain-name media_kit` run also passed after the 100-cycle
  changes. `music_video_engine_test.dart` and `system_playback_service_test.dart`
  passed on the real Linux plugin/session bus. Those are synthetic fixtures,
  not Provider-service/Android observations.
- FRB 2.13.0 generated successfully; all 24 public Rust API modules have their
  generated Dart pair, with no missing/orphaned API output.
- Existing privacy-hygiene and application-identity audits: passed. Tracked
  whitespace check and untracked-source checks contain no diagnostics.

The worktree remains dirty solely with this task's source/tests/generated
Bridge/documentation changes. These checks do not accept production refresh,
KuGou media, remote CI, mobile focus/network, or cross-session media storage.

### Exact changed-file inventory

Most QQ endpoint changes below are mechanical movement of existing typed
profile constants/Referer, not new endpoints. Generated FRB files are the
pinned regeneration for typed Queue completion.

- `ARCHITECTURE.md`
- `PROGRESS.md`
- `ROADMAP.md`
- `TECH_DEBT.md`
- `apps/flutter/integration_test/playback_engine_test.dart`
- `apps/flutter/lib/playback/foreground_audio_player.dart`
- `apps/flutter/lib/playback/foreground_playback_controller.dart`
- `apps/flutter/lib/playback/media_kit_foreground_audio_engine.dart`
- `apps/flutter/lib/playback/playback_queue_gateway.dart`
- `apps/flutter/lib/playback/queue_playback_controller.dart`
- `apps/flutter/lib/playback/track_playback_controller.dart`
- `apps/flutter/lib/src/rust/api/queue.dart`
- `apps/flutter/lib/src/rust/frb_generated.dart`
- `apps/flutter/lib/src/rust/frb_generated.io.dart`
- `apps/flutter/lib/src/rust/frb_generated.web.dart`
- `apps/flutter/test/playback/media_kit_foreground_audio_engine_test.dart`
- `apps/flutter/test/playback/playback_queue_gateway_test.dart`
- `apps/flutter/test/playback/queue_playback_controller_test.dart`
- `bridges/flutter/src/api/queue.rs`
- `bridges/flutter/src/frb_generated.rs`
- `crates/kugou-client/src/catalog.rs`
- `crates/kugou-client/src/lib.rs`
- `crates/kugou-client/src/lyrics.rs`
- `crates/kugou-client/src/profile.rs`
- `crates/kugou-client/src/search.rs`
- `crates/kugou-client/src/transport.rs`
- `crates/kugou-client/tests/search.rs`
- `crates/music-domain/src/lib.rs`
- `crates/music-domain/src/playback_queue.rs`
- `crates/netease-client/src/auth.rs`
- `crates/netease-client/src/lib.rs`
- `crates/netease-client/src/media.rs`
- `crates/netease-client/src/profile.rs`
- `crates/netease-client/src/transport.rs`
- `crates/provider-api/src/lib.rs`
- `crates/provider-api/src/media_cache.rs`
- `crates/provider-netease/src/catalog.rs`
- `crates/provider-netease/src/lib.rs`
- `crates/provider-netease/tests/catalog.rs`
- `crates/provider-qqmusic/src/lib.rs`
- `crates/qqmusic-client/src/album.rs`
- `crates/qqmusic-client/src/album_details.rs`
- `crates/qqmusic-client/src/album_favorites.rs`
- `crates/qqmusic-client/src/album_search.rs`
- `crates/qqmusic-client/src/artist.rs`
- `crates/qqmusic-client/src/artist_albums.rs`
- `crates/qqmusic-client/src/artist_search.rs`
- `crates/qqmusic-client/src/comments.rs`
- `crates/qqmusic-client/src/credential_refresh.rs`
- `crates/qqmusic-client/src/credential_verification.rs`
- `crates/qqmusic-client/src/daily_recommendation.rs`
- `crates/qqmusic-client/src/favorite_albums.rs`
- `crates/qqmusic-client/src/favorite_artists.rs`
- `crates/qqmusic-client/src/favorite_playlists.rs`
- `crates/qqmusic-client/src/lib.rs`
- `crates/qqmusic-client/src/lyrics.rs`
- `crates/qqmusic-client/src/media_resolution.rs`
- `crates/qqmusic-client/src/music_video.rs`
- `crates/qqmusic-client/src/new_albums.rs`
- `crates/qqmusic-client/src/new_songs.rs`
- `crates/qqmusic-client/src/official_playlists.rs`
- `crates/qqmusic-client/src/owned_playlists.rs`
- `crates/qqmusic-client/src/personalized_tracks.rs`
- `crates/qqmusic-client/src/playlist_containers.rs`
- `crates/qqmusic-client/src/playlist_detail.rs`
- `crates/qqmusic-client/src/playlist_search.rs`
- `crates/qqmusic-client/src/profile.rs`
- `crates/qqmusic-client/src/qq_qr.rs`
- `crates/qqmusic-client/src/radar_recommendations.rs`
- `crates/qqmusic-client/src/rankings.rs`
- `crates/qqmusic-client/src/recent_plays.rs`
- `crates/qqmusic-client/src/recommendations.rs`
- `crates/qqmusic-client/src/search.rs`
- `crates/qqmusic-client/src/track_likes.rs`
- `crates/qqmusic-client/src/transport.rs`
- `crates/qqmusic-client/src/wechat_exchange.rs`
- `crates/qqmusic-client/src/wechat_qr.rs`
- `docs/development/built-in-provider-ui-integration.md`
- `docs/research/provider-playback-session-audit-2026-10-06.md`
