# Roadmap

The Roadmap authorizes meaningful product and maintenance direction. It is not an implementation diary: detailed history belongs in Git, while exact milestone evidence belongs in the linked checkpoint reviews.

## Completed Diagnostic — isolated Tauri/Wry WebKitGTK comparison (HD-028)

**Goal:** determine whether the fatal Linux official-login failure requires
Flutter/`webview_all` embedding or can reproduce through an isolated
Tauri/Wry host sharing only the WebKitGTK/GPU stack.

**2026-09-14 result:** the repository-external Tauri 2.11.5 / Wry 0.55.1 probe
did not reproduce Flutter's default blank/DMA-BUF symptom in its 12 completed
strict default cycles, although default attempt 13 timed out waiting for
`PageLoadEvent::Finished` and therefore did not qualify as 100/100. The
one-variable SHM arm reproduced the decisive failure outside Flutter: cycle 3
reached `Finished`, then `WebKitWebProcess` received SIGSEGV on
`SkiaGPUWorker` inside NVIDIA EGL while the Tauri host was still alive. This is
strong common-layer evidence that the fatal crash does not depend on Flutter,
`GtkOverlay` or `webview_all`; it does not exclude those layers from the
separate default-rendering difference.

**Exit and next gate:** the WebKitGTK embedded-login line remains rejected.
The stop condition prevented synthetic Cookie work and any further renderer
flag. Fura source and its direct/external QR baseline are unchanged. This
diagnostic is complete; a production choice between no embedded Linux login
and a separately authorized non-WebKit CEF/Chromium experiment remains a Human
decision.

## Human Review Workstream — NetEase `webview_all` official login (HD-027)

**Goal:** obtain bounded evidence for one official NetEase Web-login candidate
without replacing the current direct QR, external official QR-confirmation or
phone-code compatibility paths.

**Execution order:** audit the exactly pinned dependency and unchanged platform
minimums; run a Linux-first visible lifecycle probe with native synthetic
HttpOnly-cookie access, complete website-data cleanup and at least 50
deterministic open/close cycles; only after that gate passes, connect a visible
login route to the existing official-Web broker, Rust candidate staging,
Account Summary verification and NetEase-only secure vault.

**Bounded exit criteria:** no unsupported platform-minimum increase; default
Linux renderer completes the probe without native crash, device disconnect,
exit hang, stale overlay or unbounded helper/resource growth; cancellation and
replacement suppress late Cookie and verification completion; product WebView
data is cleared before a fresh attempt and after success/cancel/terminal
failure; Queue, current Track, `AppPlaybackHost` and system-audio handler keep
their identities; relevant Rust/Flutter analysis, tests and Linux/Android
builds pass. Real login, restart restore and repeated interactive stability are
Human evidence.

**2026-09-14 rejected Linux candidate checkpoint:** Human evidence invalidated the
initial default-renderer confidence. The failure was reproduced in the visible
product route as a blank official page with repeated DMA-BUF EGL-import errors.
A one-variable A/B found that `WEBKIT_DMABUF_RENDERER_FORCE_SHM=1` removed the
DMA-BUF diagnostics and restored initial full/resized rendering. The local
deterministic 50-cycle suite passed, but the required actual-official-page soak
crashed `WebKitWebProcess` after cycle 17 reached `page_finished`, producing a
Flutter device disconnect. The core dump locates SIGSEGV on `SkiaGPUWorker`
inside NVIDIA EGL. The SHM production default was therefore removed and no
second renderer flag was tested. The WebKitGTK Linux candidate is rejected;
the next route requires a Human decision between a CEF/non-WebKit backend and
no embedded Linux login.

**Boundaries:** Linux remains WebKitGTK 4.1 and prior EGL/DMA-BUF/GStreamer
evidence remains authoritative. No renderer flag, forced software/X11 backend,
higher OS minimum, password/SMS/CAPTCHA automation, TLS bypass,
risk-control emulation, second credential owner/vault/player/Queue, auth
framework, sidecar or push is authorized. The external-QR baseline remains the
rollback path.

## Machine-complete Review Workstream — First-party Flutter localization (HD-026)

**Goal:** provide a coherent English and Simplified Chinese product UI with a
persisted system-following default and live language switching.

**Bounded exit criteria:** official `gen_l10n` configuration; Settings schema
v4 migration and rollback; explicit locale resolution; all Fura-authored Flutter
copy, accessibility labels and typed failure presentation moved into semantic
ARB keys; state-preserving runtime switching; English/Chinese and QQ/NetEase
widget coverage; hardcoded-literal audit; representative desktop/compact review
frames; Flutter format, analysis, tests, Linux Release and Android ARM64 Release.

**Boundaries:** no Rust localization, raw JSON bridge, localization service,
state/navigation framework, font bundle, Provider-content translation, native
startup restructuring, account automation, real-account write, redesign, or
push. Existing HD-025 NetEase account/visual acceptance and Android system-media
physical-device checks remain independent Human evidence.

**2026-09-12 machine checkpoint:** all bounded implementation exit criteria are
complete. The generated catalogs contain 843 matching messages; schema-v4
migration, locale resolution, serialized Settings writes, localized Settings
search and state-preserving live switching are covered directly. Formatting of
246 Dart files, `dart analyze`, all 552 Flutter tests, native Settings storage,
Linux Release and Android ARM64 Release pass. QQ/NetEase × English/Chinese
review frames have no observed overflow and remain Human review candidates.
The workstream now waits only for Human Simplified Chinese copy, visual rhythm
and representative physical-device acceptance; it contains no remaining
autonomous Flutter localization implementation item.

## Machine-complete Review Workstream — Existing UI integration for built-in Providers (HD-025)

**Goal:** expose the completed QQ Music and NetEase Cloud Music Core through
the existing product UI, selected persistently in Settings with QQ Music as the
default.

**Bounded exit criteria:** settings migration and rollback; static two-Provider
Bootstrap inventory; exact typed Bridge dispatch for the shared catalog,
account and Track-adjacent reads; independent credential vaults and NetEase QR;
truthful Home/Discover/Library composition; unsupported NetEase Radar, Recent
Plays and writes hidden; existing Queue/current playback retained across
selection; stale provider-scoped results rejected; full Rust/Flutter/FRB/native
machine gates and synthetic visual candidates.

**Boundaries:** reuse the present pages and Shell. No mixed Search,
cross-Provider identity interpretation, source matching/substitution, unified
likes, account migration, NetEase writes, third Provider, runtime registry,
plugin system, sidecar, stored-account automation, visual redesign or
access-control bypass. Real NetEase account behavior and aesthetics remain
Human review.

**2026-09-12 machine checkpoint:** all bounded implementation exit criteria are
complete. Pinned FRB generation, 535 Rust tests with 20 explicit live/Human
tests ignored, 527 Flutter tests, Dart/Rust format and analysis/lint gates,
Linux Release, Android ARM64 Release, and the required synthetic review frames
pass. The workstream now waits only for the real NetEase account matrix and
Human visual/runtime acceptance documented in the focused audit; it contains
no remaining autonomous implementation item.

## Acceptance Milestone — M1 First QQ Music Vertical Slice

**Goal:** sign in and restore credentials, browse the user's playlists and details, play a Track through the Rust-backed positional Queue, and follow synchronized/word-timed lyrics.

**Implemented and automated-verified:** authentication/restore, user playlists/details, media resolution, foreground playback composition, Rust Queue, synchronized lyrics, word timing, retained presentation, Linux local-media integration, and bounded Linux/Android development packaging.

**Acceptance gap:** one maintainer-operated, secret-safe observation of corrected authenticated QQ playback → Queue navigation → synchronized lyrics → word timing. Offline, anonymous, local-file, or Fixture tests cannot close this user-facing claim.

This local evidence gap does not block independently authorized maintenance. No agent may read or persist the maintainer's stored credentials to automate it.

## Completed Checkpoint — M2 Reliability and Daily-Use Quality

- **Goal:** make the first vertical slice recoverable and usable under repeated actions, failures, refresh, adaptive layouts, keyboard/pointer/touch, and accessibility semantics.
- **Outcome:** shared transport/Queue behavior, failure recovery, retained refresh, sign-out ordering, adaptive access, and bounded Linux/Android development evidence were implemented without a new state/navigation framework or background-playback architecture.
- **Checkpoint:** 2026-08-26 — [M2 review](docs/development/m2-checkpoint-review.md).

## Completed Checkpoint — M3 QQ Music Core Product Coverage

- **Goal:** expand the vertical slice into a coherent QQ Music-first catalog and personal-library client while preserving Provider, Domain, Bridge, and Flutter ownership.
- **Outcome:** Track/Artist/Album/Playlist Search; Album/Artist browsing and metadata; recommended Playlists, rankings, Radar, new Albums/Songs; favorite Albums/Artists; and retained Track-to-catalog/Now Playing journeys were implemented. Only QQ Music exists as a Provider.
- **Checkpoint:** 2026-08-27 — [M3 review](docs/development/m3-checkpoint-review.md).

## Completed Checkpoint — M4 Deliberate Material 3 Product Experience

- **Goal:** establish one official-Flutter Material 3 baseline across desktop and compact/mobile without replacing the retained presentation or music architecture.
- **Outcome:** centralized light/dark Material foundations, adaptive shell/content hierarchy, shared Track/catalog state vocabulary, Queue/Now Playing/Lyrics hierarchy, 360 px reachability, and accessibility/focus regressions were implemented.
- **Deferred:** theme personas, artwork-derived global color, expressive visual systems, and speculative design-system infrastructure.
- **Checkpoint:** 2026-08-27 — [M4 review](docs/development/m4-checkpoint-review.md).

## Completed Checkpoint — M5 Mainstream QQ Music Product Experience

- **Goal:** establish a truthful Home-first mainstream product with distinct retained Home, Discover, Search, Library, and persistent Now Playing responsibilities.
- **Outcome:** bounded Home, coherent Library sections, Rust-authoritative sequential/shuffle and repeat modes, shared Track context, read-only comments, and one Track-associated MV journey were implemented.
- **Boundaries:** no remote mutation, downloads, background-playback architecture, additional Provider, generic social/video platform, or state/navigation replacement.
- **Checkpoint:** 2026-08-27 — [M5 review](docs/development/m5-checkpoint-review.md) and [product-completeness audit](docs/development/m5-product-completeness-audit.md).

## Completed Checkpoint — M6 Core Compatibility Evidence

- **Goal:** validate the newly introduced anonymous comments and Track-associated MV protocol paths without account material or new product capability.
- **Outcome:** default-ignored live gates pass. Evidence corrected comment identity to bounded opaque text and filters only the observed blank deleted-row shape while preserving raw-row pagination.
- **Evidence boundary:** this is selected direct-client compatibility, not full-application behavior, authenticated playback, remote MV playback, broad catalog quality, or release readiness.
- **Checkpoint:** 2026-08-27 — [M6 review](docs/development/m6-checkpoint-review.md).

## Deferred Workstream — M7 Page-by-Page Product UI Integration

**2026-09-09 scheduling override (HD-023):** retain every current visual candidate without editing or accepting it. Human visual review is deferred while NetEase Core work is active. The sequence below is historical UI scope, not current execution.

**Goal:** integrate the existing product one page at a time against Human-approved Stitch/Figma sources so it reads as a mature QQ Music-familiar Material 3 client, using only truthful capabilities and no copied branding, proprietary assets, fake personalization, or new framework.

**Current sequence:** The maintainer has redirected the current Home candidate to one consolidated recommendation pass. The public hero must rotate among real public recommendations instead of remaining fixed for a day, while Daily 30, Radar, personalized Tracks/Playlists, public Playlists, new songs, and current-Track related listening remain recognizably distinct. Expanded Now Playing and Liked Songs remain implemented and unaccepted. After canonical wide and compact Home renders, work stops for maintainer visual review; another page does not start autonomously.

**Current scope:** Preserve the approved Home composition and Shell. Use the existing public-playlist collection for a bounded, controllable spotlight carousel with a date-stable starting item; retain explicit Daily, Radar, personalized Playlist/Track, and related-Track semantics; and expose the existing public latest-new-song capability as its own authenticated Home section without replacing personalized content. Generic content may not masquerade as an exact recommendation capability. No new endpoint, heterogeneous feed runtime, Provider, navigation framework, or state framework is authorized. After targeted Flutter checks plus canonical desktop and mobile renders, implementation stops for Human visual review.

**Boundaries:** approved frames are visual sources of truth, while implementation must preserve retained state, accessibility, truthful Provider semantics, and the existing Flutter/Rust/music ownership. M7 is product integration, not a design-framework, navigation-framework, or architecture-rewrite project.

**Prior Home evidence:** HD-006 and HD-007 produced the current full-height desktop Sidebar/Main Region and a truthful six-section Home snapshot. HD-008 then paused presentation while the Core capability audit completed; HD-009 supersedes that scheduling pause and authorizes the approved Stitch-driven Home replacement.

## Authorized Capability Workstream — Cross-Platform System Playback Adaptation

**Goal:** integrate the existing single music playback owner with native operating-system media surfaces on Android, iOS, macOS, Linux, and Windows without replacing `audioplayers`, duplicating the Rust Queue, or exposing QQ media URLs and credentials.

**Phases:** (1) one platform-neutral Flutter adapter for provider-neutral metadata/state and command delegation; (2) Android media foreground service plus audio focus, lock-screen/notification and headset controls; (3) iOS/macOS remote-command and background-audio wiring; (4) Linux MPRIS and Windows SMTC wiring; (5) manual GitHub Actions development packaging on each native build host; (6) per-target runtime acceptance wherever a real environment is available.

**Bounded exit criteria:** all platform shells package the appropriate adapter; current Track metadata, play/pause/stop, previous/next and supported seek/mode state remain projections of the existing controller; interruptions and audio-route loss pause safely; stale system state is cleared when the owner detaches; relevant unit/integration/build gates pass; each runtime claim is accepted independently. Windows timeline/seek cannot be claimed until TD-008 is resolved or the chosen adapter proves it.

**Boundaries:** no second player, Queue, resolver, background download, persistent Queue/history, autoplay radio, sidecar, raw QQ data, stored-account automation, or release identity decision. A system surface is another input/output adapter over the same owner, not a new playback domain.

**Current evidence:** the shared adapter and all five platform registrations are implemented. Unit regressions prove command/state delegation and terminal clearing; the current Linux session initializes MPRIS and produces a Release build; Android x64 Debug packages. HD-015 authorizes a manual, development-only CI workflow for the remaining native build hosts; its committed workflow must still run successfully before it becomes platform build evidence. Android device behavior and Apple/Windows runtimes remain human/environment gated.

## Completed Core Workstream — Media Source Separation

**Goal:** make Catalog/Account Provider ownership distinct from immediate-playback Media Source Resolution while preserving QQ Music as the only bundled first-class catalog and production source.

**Bounded exit criteria:** generic playback enters a small typed Rust media-source coordinator; the QQ resolver alone interprets QQ Track identity and preserves current guest/authenticated quality behavior; the Flutter/Rust media Bridge is provider-neutral and cancellable; generic Flutter resolution no longer owns QQ vault cleanup; a test-only synthetic resolver proves routing is not hardwired to `QQMusicProvider`; Core and affected Flutter gates pass.

**Boundaries:** no additional production source, cross-service matching, universal identity, dynamic plugin/runtime discovery, marketplace, sidecar, source selector, Queue/player/system-media redesign, speculative format/quality, stored-account automation, or access-control bypass. Existing manual and target-specific evidence remains pending.

**Outcome:** generic playback now enters one typed `MediaSourceCoordinator` and routes QQ Tracks to a distinct QQ-owned resolver; `QQMusicProvider` remains the first-class Catalog/Account owner but is no longer the generic playback-routing authority. The public Bridge and generic Dart gateway are provider-neutral, QQ authentication owns QQ-vault rejection cleanup, and a test-only non-QQ resolver plus an unsupported-provider native integration prove the separation without adding a second production source.

**Completed:** 2026-09-01. Full Rust tests/fmt/strict Clippy, pinned Bridge generation and orphan audit, Dart format/analyze, Flutter tests, and Linux native Bridge integration are the machine evidence. Live authenticated QQ playback and target-specific runtime checks remain independent maintainer/environment evidence.

## Active Core Workstream — QQ Capability Evidence and Auth-Aware Protocol Strategy

**Goal:** keep each public QQ capability facade stable while making its private protocol choice deterministic, auth-aware, evidence-driven, and able to distinguish protocol compatibility, authentication, content availability, and session-level risk outcomes.

**Bounded exit criteria:** the current capability/protocol inventory is recorded with separate anonymous/authenticated evidence; a small private Client policy can express return, bounded retry, evidence-safe fallback, and mandatory stop; at least one observed risk outcome is typed and regression-tested without changing provider-neutral semantics; alternative paths remain evidence-only unless their exact request, bounded output and failure behavior are independently supported; relevant Rust gates pass.

**Boundaries:** one `QQMusicProvider`, one QQ credential owner, existing Media Source separation, unchanged provider-api/Bridge/Flutter contracts, and no automatic endpoint racing or learning. No new Provider, service aggregation, dynamic strategy registry/plugin runtime, sidecar, risk-control evasion, access-control bypass, stored-account automation, UI work, or production fallback based only on static source similarity is authorized.

**Current evidence:** the production inventory and evidence-only candidates are in [the QQ capability protocol matrix](docs/research/qqmusic-capability-protocol-matrix.md). HD-021 permits evidence-complete anonymous, read-only candidates to be promoted autonomously; public Playlist Detail now uses the verified anonymous context. Search alternatives remain evidence-only after the current Primary produced rate-limit code `2001`, and VKey alternatives have no demonstrated compatibility gap. Authenticated endpoint promotion and account/device/region-dependent comparisons remain Human evidence rather than autonomous live probes.

## Completed Checkpoint — First-Release Core Capability Completion

**Goal:** freeze page-level visual redesign and complete the smallest truthful Account, Home-data, Library, Playback/media, Catalog, Settings, Platform, and Track-related capability foundation needed by the already authorized QQ Music-first first release.

**Execution:** maintain one repository-wide capability matrix, implement one bounded capability at a time, run layer-appropriate tests, and rerank current evidence. Safe reads and offline mutation semantics are authorized; stored account automation and autonomous real-account writes are forbidden.

**Exit criteria:** every required capability in `docs/development/first-release-capability-audit.md` is `VERIFIED` or carries an exact `EVIDENCE_BLOCKED`, `ENVIRONMENT_BLOCKED`, or `HUMAN_DECISION_REQUIRED` boundary, with no untracked executable `MISSING` first-release capability. A checkpoint proves core readiness for later UI wiring, not user-visible product completion.

**Non-goals:** page redesign, Settings-page design, all QQ APIs, social/video or download expansion, another Provider, background-service architecture without product authority, real-account mutation automation, or a generic capability, settings, paging, or dependency-injection framework.

**Outcome:** the repository-wide audit contains no required executable `MISSING` capability. Account summary, truthful Home-data contracts, bounded library mutations, two-quality media, typed Settings, and related Track foundations are available through their intended layers. At that checkpoint, playlist rename, Artist mutation, authenticated M1 playback/lyrics, unavailable target runtimes, Popular Programs, background playback, and release work retained exact local blockers; HD-013 and HD-014 later resolved the product decisions for Popular Programs and system playback without rewriting this historical result.

**Checkpoint:** 2026-08-28 — [Core capability review](docs/development/first-release-core-capability-checkpoint.md).

## Completed Maintenance Pass — Complexity Paydown

**Goal:** reduce accumulated implementation and governance complexity while preserving every existing user-visible behavior, retained state, test, supported flow, and architecture boundary.

### Outcome

- Authenticated destination, Library subsection, local-detail, and Back state are explicit while retained widgets, focus, playback, Queue, and lyrics ownership remain unchanged.
- Post-authentication dependencies are grouped by responsibility while constructor injection and granular test overrides remain explicit.
- Identical Search failure/retry semantics and repeated catalog Queue test setup are shared without generic controller, Bridge, navigation, or state frameworks.
- Governance records durable evidence/current scheduling instead of microtask ceremony or implementation diaries.

### Preserved boundaries

- No new QQ Music endpoint, Provider, product capability, Search type, recommendation surface, mutation, download, background-playback architecture, local/fallback Provider, Home content, theme, visual redesign, state framework, or navigation framework.
- Do not flatten QQ protocol → Provider → Domain → Bridge → Dart presentation boundaries solely to reduce file count.
- Do not delete regressions or evidence documents merely to reduce totals.

**Verified on 2026-08-27:** all full Rust, Dart/Flutter, Linux release-build, and required Linux integration gates passed. The audit, outcomes, claim limits, and final self-review are recorded in [the complexity-paydown review](docs/development/complexity-paydown-review.md).

## Later Evidence-Gated Direction

The preceding QQ Core-capability checkpoint is complete. M7 records retained Human visual candidates; HD-023 now freezes that UI workstream and makes NetEase CORE the active workstream below. Automated tests do not establish visual product completion.

Offline/cache behavior, a narrow local-library capability, or media fallback require demonstrated user value and separate Roadmap authority. They must not turn the product into a multi-service aggregator. Release identity/signing and external distribution remain governed by HD-001 and the linked technical debt.

## Active Core Workstream — NetEase second built-in Provider (HD-023)

Implement `netease-client` → `provider-netease` → existing provider-neutral contracts with exact provider-scoped identities. Track Search is the first vertical slice; public Playlist Detail follows. Complete bounded Album/Artist Search and browsing, Track detail, line-synchronized lyrics, evidence-backed rankings/public recommendations, and standard authorized media resolution. Audit each current Provider trait; extend only proven provider-neutral gaps. Prefer simple static built-in selection and exact resolver routing.

Anonymous evidence must be serial, read-only, explicitly gated, ignored by default and hard-budgeted; fixtures establish deterministic safety. Then implement evidence-backed QR/session/restore/account/library/authenticated recommendation foundations up to `HUMAN_EVIDENCE_REQUIRED`. Do not automate real accounts. No Flutter integration, cross-service aggregation/matching/substitution, third Provider, dynamic runtime, sidecar, or access-control bypass. Finish with workspace tests, formatting, strict all-target Clippy, and logical local commits without push.

**NetEase machine checkpoint, 2026-09-09:** anonymous/public Core and authenticated offline foundations are implemented; the full remaining-work audit and verification checkpoint live in `docs/research/netease-remaining-work-audit.md`. Real-account QR/restore/library/recommendation/media claims remain `HUMAN_EVIDENCE_REQUIRED`. This does not activate UI integration or resume deferred visual candidates.

**HD-024 hardening/parity checkpoint, 2026-09-09:** one native NetEase owner now serves media and every future native edge; QR-confirmed credentials survive transient verification as pending candidates; a Human-only account-read matrix is compiled but unrun. Public Playlist/liked identities and whole Albums support deterministic windows above the former 1,000-row ceiling under body-budget-derived resource caps. Comments, related Tracks, exact-category new songs/new Albums and Track-associated MV are implemented and passed one serial anonymous compatibility window; a separate >1,000-Track public Playlist window passed. NetEase recent history remains evidence-blocked, while actual account reads and unavailable host packaging remain Human/environment evidence. No UI work is activated.
