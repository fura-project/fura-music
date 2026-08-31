---
execution:
  mode: HUMAN_GATED_REGRESSION
  state: ACTIVE
  acceptance_milestone: M1
  active_workstream: SYSTEM_PLAYBACK_PLATFORM_ADAPTATION
  current_task: CROSS_PLATFORM_PACKAGE_REGRESSION
  next_action: PUSH_RERUN_AND_ANDROID_RUNTIME_RETEST
---

# Current State

- The first-release Core-capability workstream checkpointed on 2026-08-28. Its audit has no required executable `MISSING` item; every remaining gap is exactly evidence-, environment-, or human-decision-blocked. See `docs/development/first-release-core-capability-checkpoint.md`.
- M2 through M6 are checkpointed. HD-013 redirects the active M7 visual-review surface to a bounded Home data-slot correction; Liked Songs and Expanded Now Playing remain implemented and unaccepted.
- M1 still lacks the maintainer-operated real QQ playback → Queue → synchronized/word-timed lyric observation. The checkpoint does not close or bypass it.
- Home no longer presents Popular Programs. `More from your listening` uses a distinct, cancellable current-Track related read rather than relabeling personalized Tracks. Public Feed evidence showed valid personalized playlists with `http://qpic.y.qq.com` artwork; the Client now upgrades only that verified QQ image host to HTTPS and still rejects other cleartext artwork. The previous anonymous modern related request returned successful empty envelopes for bounded public seeds; the Client now uses the independently implemented signed route whose ignored live regression returned a non-empty bounded Track set. Offline and live protocol regressions pass; an authenticated Home rerun is still needed to confirm visible production recovery.
- The maintainer redirected the current UI task to keep the normal adaptive product Shell visible while signed out and present authentication in a modal. That modal now offers QQ Web QR, the already verified WeChat QR path, and phone plus one-time SMS code without collecting a password. Public Home/Discover/Search remain reachable; account-only Home and Library surfaces show explicit sign-in states instead of launching account reads. The multi-method implementation is offline-verified; anonymous QQ QR bootstrap/poll also passed, while confirmed QQ QR and phone delivery/login still require maintainer operation. The signed-out Shell candidate still awaits desktop/mobile visual review.
- Guest media resolution no longer fails before transport. Signed-out playback now requests only anonymous M500 standard quality with `uin=0` and no Cookie or fabricated credential; a bounded live gate found a playable source among ten public Search results. Tracks for which QQ returns no anonymous source still offer sign-in without claiming a restriction reason. Authenticated high-to-standard fallback is unchanged.
- HD-014 now authorizes system playback over the existing single Flutter playback owner. One thin `audio_service` handler publishes provider-neutral current metadata, Queue mode and position, delegates system transport/seek/mode commands to the existing Rust-backed Queue/controller, and configures music audio focus plus interruption/noisy-device pause. A maintainer Linux run reproduced stale/non-seekable system progress plus unavailable shuffle/repeat controls: the pinned generic MPRIS adapter stored only one position sample and left those commands incomplete. Linux now uses a project-owned MPRIS edge with projected position, typed Track identity, absolute/relative seek, truthful capabilities, and bidirectional shuffle/repeat/volume. Unit regressions and a real session-bus integration pass; KDE/GNOME shell retest remains required. Other platform evidence is unchanged.
- HD-015 authorizes a manual GitHub Actions packaging gate for maintainer runtime testing. Run 33395804013 passed the offline quality, Android, iOS Simulator, and macOS jobs; Linux failed during apt dependency installation and Windows failed during the Release build. The Android ARM64 artifact exposed a separate packaging defect: its Release manifest lacked Internet permission even though the Rust bridge library compiled and loaded. The main manifest now declares normal network permissions, the workflow verifies both Internet permission and the ARM64 Rust payload, Linux dependency installation has bounded transient-failure retries, and Windows is pinned to the stable `windows-2022` runner instead of the moving `windows-latest` label. A new remote run and physical Android retest remain required; these local changes do not establish either result.

# Current Capability Boundary

- Later UI can reuse typed Account, Home recommendation, Library read/mutation, Search, Discover, foreground playback/Queue/mode, Lyrics, Comments, MV, and Settings foundations without raw QQ responses or fabricated semantics.
- Popular Programs is excluded by HD-013. System playback is authorized by HD-014 without changing the single-player/Rust-Queue ownership. Playlist rename and Artist mutation remain protocol-evidence-blocked. Physical Android and Apple/Windows system-playback runtime claims remain environment-blocked.
- Remote-write foundations have independent protocol evidence and strict offline lifecycle coverage, but this repository did not mutate the maintainer's account. Confirmation, refresh, and maintainer-operated live acceptance remain later UI/evidence work.
- Personalized recommendation availability and quality are not authenticated-account verified. The authenticated personalized Track set and anonymous current-Track related set are distinct and may not substitute for each other.

# Current Scheduling

- There is no remaining safe agent-only Core capability task supported by the audit. Do not invent another endpoint, Provider, framework, or refactor to keep producing commits.
- The maintainer redirected the current bounded regression candidate to the Liked collection tabs. Songs retain the approved dense table/list presentation; real user playlists are split by typed owned/saved semantics; favorite Albums reuse the existing typed collection; and unsupported program/video account collections remain explicit rather than being fabricated from playlists or Track-associated MV.
- Home still needs a maintainer authenticated rerun for Daily/personalized recommendation availability and the corrected personalized/related recommendation presentation. Liked Songs and Expanded Now Playing remain implemented and unaccepted.
- The current candidate intentionally omits unsupported download and batch-edit controls. Program and video tabs expose the requested information architecture, but real collection content remains capability-blocked in the current Human-gated regression mode; synthetic review content does not enter production and no account data was accessed.
- No other page may begin before maintainer visual acceptance or another explicit Human redirect. Automated checks and the bounded Material 3 review cannot supply that acceptance.
- Do not automate stored-account access, real-account mutation acceptance, or secret-bearing screenshots/fixtures.
- QQ Web QR approval/credential restore and phone-code delivery/authorization remain maintainer-operated compatibility observations; the agent may not scan, authorize, or submit a real phone number autonomously. Phone authorization is a reverse-engineered private-client protocol, not an official public API, and remains visibly experimental until live compatibility is established.
- System playback now needs bounded maintainer/runtime checks: Android notification/lock-screen controls, media buttons, audio focus and task-background continuity; Linux KDE/GNOME should recheck that progress advances, scrubbing seeks the current Track, and shell shuffle/repeat round-trip to the app; and later iOS/macOS Control Center plus Windows SMTC when those hosts are available. Platform gaps must remain separate rather than being inferred from another target.
- The immediate packaging action is to commit/push the Android/CI correction, manually rerun `Cross-platform development packages`, and preserve each job's exact result. Install the newly produced ARM64 APK on a physical Android target and confirm that signed-out Search/Home data loads before broader account or system-media testing. A failed platform job is a target-specific build regression, not evidence that another artifact works or that the whole project is release-ready.

# Blockers

- **M1 evidence:** maintainer-operated ordinary QQ Track playback → Queue navigation → synchronized lyrics → word timing.
- **Protocol evidence:** playlist rename and Artist follow/unfollow need independent current request/success evidence before Client work.
- **Target environments:** physical Android and Apple/Windows secure-storage/system-media behavior cannot be established on this host. Windows SMTC timeline/seek also remains limited by TD-008.
- **Release:** production identity, signing, external distribution, and native-video notices remain blocked by HD-001 and TD-002/TD-006.

# Pending Human Decisions

- **HD-001:** final product/display name, platform identifiers, signing custody, and distribution ownership.

# Important Evidence Limits

- Offline and Widget tests prove implemented rules and retained presentation behavior, not current authenticated QQ CDN playback, personalized recommendation quality, or broad live catalog compatibility.
- Linux local media, packaged Bridge, and development builds do not prove physical-device audio focus, hardware video decode, unavailable operating systems, or release readiness.
- The locally rebuilt ARM64 Release APK proves the final package declares Internet access and contains the ARM64 Rust bridge library. It does not prove physical-device DNS/TLS reachability, current QQ compatibility, authenticated behavior, or that rerun 33395804013's successor will pass Linux/Windows.
- Linux MPRIS unit and real session-bus integrations prove service registration, property signatures, progressing position calculation, Track-bound absolute/relative seek dispatch, and shuffle/repeat round trips through the existing handler. They do not prove a particular KDE/GNOME shell renders or invokes every supported control correctly. Android packaging still does not prove lock-screen/notification behavior, task-removal continuity, or headset controls; Apple/Windows runtime behavior remains unverified.
- Home, Liked Songs, and Expanded Now Playing remain unaccepted. Home is the current visual-review candidate; canonical synthetic renders and targeted tests do not prove Human visual acceptance, authenticated personalization availability, or related-song quality across the catalog.
- Historical research/checkpoint documents remain evidence snapshots. Current scheduling is governed by `AGENTS.md`, `ROADMAP.md`, and this file.
