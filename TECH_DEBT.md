# Technical Debt

Technical debt is reviewed after each finite task. States are `Open`, `Triggered`, `Scheduled`, `In Progress`, `Resolved`, and `Accepted Permanently`.

## TD-001 — System-Rust bridge builds bypass Cargokit

**Status:** Open

**Problem:** `flutter_rust_bridge` 2.13.0 generates a Cargokit backend that invokes `rustup` unconditionally. The Arch development environment intentionally uses supported system `rustc` and `cargo` packages, where installing rustup would conflict with the system toolchain. Linux x64 therefore has a small direct-Cargo CMake integration. Android uses a project-owned Gradle task only on Linux hosts without `rustup`; it accepts one explicit ARM64 or x64 target, builds the matching standard library from the distribution `rust-src` package, and otherwise leaves generated Cargokit in place.

**Why accepted:** Linux is first-class and the direct build uses the same Cargo workspace, lockfile, crate type, and Rust compiler already validated by the core suite. Replacing the whole bridge or installing a conflicting toolchain would be larger and riskier during the executable-foundation task.

**Impact:** The Linux CMake and Linux-host Android Gradle integration are no longer fully generator-owned. Android system-Cargo support is deliberately limited to one explicit ARM64 or x64 build. Matching system `rust-src` is installed; a clean release ARM64 build compiled `std` from it, produced a complete single-ABI APK, passed 16 KB alignment/signature checks, and started under the AVD's ARM64 translation. Native x64 packaged FFI passed on Android 16.

**Risk:** Re-running bridge integration could overwrite the customization; other Android ABI sets and non-Linux target builds still need verified toolchain paths. Future dependency changes could reintroduce incomplete ABI advertising or compiler-runtime symbols unless the current guards remain. Emulator and translation success do not prove physical-device behavior.

**Suggested solution:** Adopt upstream Cargokit/native-assets system-Rust support when it can replace the two localized paths without losing the current Cargo lockfile, NDK API 24 toolchain, target-aligned ABI filtering, NDK compiler-runtime linkage, unresolved-symbol gate, or 16 KB page alignment. Add another ABI only when a Roadmap or runtime target requires it.

**Trigger condition:** The Android ARM64 build and x64 emulator triggers were handled on 2026-08-26. Reassess when FRB/Cargokit gains supported system-Rust builds, regeneration overwrites either customization, or another target/ABI becomes required.

## TD-002 — Release identity and signing use generated defaults

**Status:** Triggered

**Problem:** Platform shells still use Flutter-generated application branding and development signing defaults. Android release builds currently use the debug signing configuration.

**Why accepted:** Development builds were needed to prove the in-process architecture and target packaging without distributing binaries. Inventing release identity, signing custody, and store metadata would expand scope and introduce credential risk.

**Impact:** Locally built artifacts and HD-015's seven-day manual GitHub Actions artifacts are development artifacts only and must not be published as releases.

**Risk:** An accidental release build could look production-like while carrying development identity or debug signatures.

**Suggested solution:** After HD-001 is decided, define project-owned application icons, display names, identifiers, and a secret-safe per-platform signing workflow.

**Trigger condition:** Triggered on 2026-08-26 when M1 packaging produced and inspected Android ARM64/x64 APKs and continued Linux release bundles. HD-015 later authorized only short-lived manual CI test artifacts; production resolution remains blocked on HD-001 and unrelated development continues.

## TD-003 — Persisted credential restore lacked server verification

**Status:** Resolved

**Problem:** `QQMusicProvider` serialized a successful credential into a versioned opaque document and startup imported it, but a structurally valid candidate was not verified with QQ Music. Closing the application therefore could not regain an authenticated session safely.

**Why accepted:** Persistence, local import, and network verification are separate failure domains. The staged local slice first proved absence, corruption, format version, invariant validation, and expiry behavior without allowing a stored key to imply server validity; the UI reported verification as pending until this network step was implemented.

**Impact:** Resolved for the implemented path: an eligible stored candidate now reaches authenticated state only after QQ Music accepts it. The platform vault runtime and real-account acceptance gaps remain TD-004 and a documented validation risk respectively.

**Risk:** Future error mapping could regress by treating a transient failure as rejection, or stale verification could overwrite a replacement login.

**Suggested solution:** Implemented with the named user-info RPC, exact attempt IDs, explicit rejection-code mapping, retained transient failures, and cross-layer regression tests. Secure storage is deleted only at the Flutter platform edge after explicit rejection.

**Trigger condition:** Resolved on 2026-08-25. Reopen if QQ Music response evidence changes, a transient failure signs the user out, or a stale verification can promote after replacement/cancellation.

## TD-004 — Secure-storage runtime behavior is not verified on every target

**Status:** In Progress

**Problem:** Linux and Android 16 x64 now have passing disposable write/read/delete integrations. iOS, macOS, and Windows implementations have not been built or run in this checkout.

**Why accepted:** The Linux test uses an isolated randomized non-account key, never calls `deleteAll`, and confirms absence in `finally`. Not every other target runtime is available on this host, and claiming runtime verification from generated registrants would be false.

**Impact:** Linux's configured adapter and Android's x64 emulator path are runtime-verified on this host. An unverified target may still have an entitlement, keyring, or plugin issue that leaves the user authenticated only for the current process; the UI reports that failure without discarding the active Rust credential.

**Risk:** A non-Linux build could appear to support restart restore while its platform vault is inaccessible, or future changes could weaken the disposable test's cleanup boundary.

**Suggested solution:** Reuse the disposable non-account round-trip pattern on each target before that target is accepted for authenticated distribution; keep unique keys and guaranteed cleanup instead of broad vault deletion.

**Trigger condition:** Linux was resolved on 2026-08-25 and the Android M1 instance on 2026-08-26. Apple and Windows targets must resolve their own instances before their distribution.

## TD-005 — Favorite-playlist aggregation has a 1,000-row safety ceiling

**Status:** Open

**Problem:** The complete QQ Music playlist operation follows at most ten favorite pages of 100 rows. If QQ Music still reports `hasmore`, the Provider returns `InvalidResponse` instead of continuing indefinitely or silently returning a partial library.

**Why accepted:** QQ Music is an unstable external service, yakult's current implementation independently uses the same 1,000-row ceiling, and this checkout has no sanitized evidence for accounts exceeding it. A finite bound is required before the loop can sit behind one cancellable Bridge operation.

**Impact:** An account with more than 1,000 favorited playlists cannot load the combined library, although its created-only operation remains available internally.

**Risk:** The UI may show a structural-response error for a legitimate unusually large account.

**Suggested solution:** Replace the fixed aggregate call with an evidence-backed higher bound or incremental user-library pagination that keeps cancellation and account-replacement checks exact. Never silently truncate.

**Trigger condition:** Reassess when a sanitized fixture or controlled integration returns `hasmore` after page ten, or before public alpha if large-library support becomes an acceptance requirement.

## TD-006 — Native video distribution notices are not assembled

**Status:** Open

**Problem:** M5.5 adds the MIT-licensed `media_kit` packages and their bundled native playback libraries. Development builds intentionally do not yet contain a project-owned, per-platform inventory and notice bundle covering the exact libmpv/FFmpeg build flavor and all applicable native-library terms.

**Why accepted:** The dependency decision used the upstream default non-GPL video flavor and bounded local Linux/Android packaging evidence. No artifact is authorized for external distribution while HD-001 remains pending, so assembling production notices before the final artifact shape and release ownership exist would be premature.

**Impact:** Development and testing can continue, but an MV-capable binary must not be published as a release until its exact native dependency inventory and required notices/source or relinking information have been reviewed and included.

**Risk:** Publishing without that review could omit license text or another obligation imposed by the native media stack. Dependency updates could also change the bundled build flavor or license set without an obvious Dart API change.

**Suggested solution:** During authorized release preparation, inventory each platform artifact, verify the selected native build configuration against upstream provenance and licenses, include the required third-party notices and corresponding source/relink information, and add a repeatable release check that detects dependency or build-flavor changes. Obtain human/legal guidance if the applicable distribution terms remain uncertain.

**Trigger condition:** Schedule together with TD-002 after HD-001 is resolved and before the first external MV-capable artifact is distributed; reassess immediately if the media packages or native build flavor change.

## TD-007 — Remote library mutations duplicate single-use lifecycle adapters

**Status:** Resolved

**Problem:** Liked-Track and owned-playlist Track membership deliberately use two explicit Bridge handles and Dart gateways with nearly identical single-use cancellation, typed unknown-outcome, and credential-cleanup mechanics.

**Why accepted:** Two concrete operations established the real common lifecycle while keeping their desired-state types and Provider contracts clear. A generic remote-mutation framework before that evidence would have been speculative and harder to audit for account safety.

**Impact:** The proven single-use Rust lifecycle and Dart credential-cleanup rule are now shared; operation-specific typed failure mapping remains intentionally explicit.

**Risk:** A third copied mutation path could drift by reporting an uncertain remote write as a definitive failure, retrying it, or clearing credentials for a non-rejection.

**Suggested solution:** Implemented as one private Bridge lifecycle and one narrow Dart cleanup helper. Keep operation-specific typed inputs/results and Provider-owned identity parsing separate.

**Trigger condition:** Triggered and resolved on 2026-08-28 before the selected create-playlist operation entered implementation. Reopen only if another proven lifecycle rule starts being copied across remote mutations.

## TD-008 — Windows SMTC adapter lacks mature timeline and seek support

**Status:** Open

**Problem:** Windows system playback currently uses `audio_service_win` 0.0.3. It implements SMTC registration, metadata, play/pause/stop/previous/next callbacks and coarse playing state, but its platform adapter does not publish a playback timeline, accept seek, or expose the Queue. The package is young and has not been built or run on a Windows host in this checkout.

**Why accepted:** The package preserves the shared `audio_service` handler and single playback owner, provides the bounded transport surface already requested, and avoids inventing a second Windows-only playback architecture. No Windows runtime or release claim is being made.

**Impact:** Windows can be wired for basic SMTC transport and metadata, but this repository cannot yet claim system progress scrubbing, timeline accuracy, Queue selection, or runtime compatibility there.

**Risk:** A Windows build may expose plugin or lifecycle defects, and users could see controls whose capabilities differ from Android, Apple, or Linux. A dependency update could also change native behavior without a Dart compile error.

**Suggested solution:** Before Windows system playback acceptance, run a native Windows integration against the existing handler, verify metadata and every advertised command, and either contribute/consume an evidence-backed timeline/seek implementation or keep those actions explicitly unsupported. Review the exact package/native license inventory with release preparation.

**Trigger condition:** Schedule when a Windows build environment becomes available or before any Windows system-playback/release claim. Reassess immediately if the platform package changes ownership, compatibility, or API surface.

## TD-009 — Linux MPRIS protocol edge is project-owned

**Status:** Open

**Problem:** The stable generic MPRIS adapter retained only a static playback-position sample and left relative seek, shuffle, and repeat unavailable despite the application's shared handler supporting them. Linux therefore owns a bounded D-Bus/MPRIS `AudioServicePlatform` implementation instead of delegating that protocol edge to `audio_service_mpris`.

**Why accepted:** The defect was reproduced by the maintainer and confirmed in the pinned adapter source. Its current prerelease still lacked the complete timestamped position, relative seek, and required Track identity behavior. Adding timers or duplicate mode state to the playback controller would hide the protocol defect and violate the single-owner boundary; a localized adapter with protocol and real session-bus tests fixes the root layer.

**Impact:** Linux progress, seek, shuffle, repeat, and volume can map to the existing handler without a second player or Queue, but the repository now maintains MPRIS introspection, properties, methods, and signal behavior.

**Risk:** A future MPRIS specification or desktop-shell expectation could diverge from the local edge, while an upstream adapter may eventually make this code unnecessary. A session-bus test cannot prove every KDE/GNOME presentation behavior.

**Suggested solution:** Keep the edge isolated and regression-tested against the current MPRIS contract. Prefer replacing it with an upstream stable implementation when that implementation demonstrably supports timestamp-projected position, required `mpris:trackid`, absolute and relative seek, truthful capabilities, and bidirectional shuffle/repeat without changing Queue ownership.

**Trigger condition:** Reassess when `audio_service_mpris` publishes a stable compatible release, the MPRIS specification changes, or a KDE/GNOME runtime retest exposes behavior not covered by the current protocol/session-bus gates.

## TD-010 — Authenticated Flutter Shell concentrates unrelated state

**Status:** Triggered

**Problem:** `_UserLibraryPageState` remains the authenticated composition root for primary and retained-detail navigation, seven long-lived controllers/caches, focus restoration, Settings hierarchy, collapsed page headers, playback-quality orchestration, credential-rejection routing, and sign-out. These responsibilities are still layer-correct, but their shared lifecycle makes a local Shell change expensive to review and easy to couple to unrelated state.

**Why accepted:** The current Human-gated repair extracted the duplicated playback-quality semantics, isolated current-Track identity from high-frequency playback notifications, and moved optimistic Settings persistence into a focused controller. A wholesale Shell rewrite or new state-management/navigation framework would exceed the reproduced regressions and risk accepted navigation, focus, and retained-page behavior.

**Impact:** Changes to Settings, navigation, Liked/Discover header collapse, or playback composition still touch one large State class and often require broad Widget coverage even when the visible change is narrow.

**Risk:** Another cross-cutting Shell feature could reintroduce broad listeners, duplicate lifecycle guards, or stale route/focus state. File size alone is not the trigger; a repeated change spanning multiple unrelated responsibilities is.

**Suggested solution:** Incrementally extract one existing semantic owner at a time when a concrete change touches it: first retained Shell navigation/focus state, then Settings hierarchy composition, while keeping page controllers and the single Queue owner unchanged. Require before/after interaction tests and do not introduce a generic state-management framework.

**Trigger condition:** Triggered by the 2026-09-08 audit after playback quality and large-playlist search both added state to the same composition root. Schedule the first extraction when the next authorized defect or feature must modify at least two of navigation/focus, Settings, collapsed headers, or playback orchestration.

## TD-011 — NetEase large collection windows refetch whole upstream metadata

**Status:** Open

**Problem:** Current NetEase public/private Playlist detail returns the complete `trackIds` table, liked songs returns one complete ID list, and Album detail returns the complete song array. Fura resolves only a requested at-most-100 row window, but a later Playlist/Album page can repeat the whole metadata request because no evidenced server-side identity cursor exists.

**Why accepted:** Current `api-enhanced` and its Rust-port counterpart `ncm-api-rs` both expose local slicing over whole Playlist metadata; the authenticated liked and Album operations likewise provide no evidenced page cursor. Fura now rejects bodies above 2 MiB and uses decoded-memory caps derived from that budget instead of silently truncating at 1,000. Inventing offset parameters or an unbounded cache would be less reliable.

**Impact:** Legitimate collections up to 16,384 Playlist/liked identities and 4,096 Album Tracks are readable, but distant-page navigation can repeat bandwidth and decoding work.

**Risk:** Very large but in-bound collections may feel slower or consume avoidable network traffic, while collections above the caps fail explicitly.

**Suggested solution:** If real usage demonstrates this cost, cache the validated identity/Album snapshot inside the exact Provider generation with bounded lifetime and replacement/sign-out invalidation, or adopt a current server-side cursor only after protocol evidence. Keep Track-detail windows at 100 and never return partial identity tables as complete.

**Trigger condition:** Reassess after a Human large-account latency observation, a service response above the derived caps, or reliable evidence of a true server-side paging operation.

## TD-012 — Native startup media strings are not locale-aware

**Status:** Open

**Problem:** Flutter presentation now resolves English and Simplified Chinese at
runtime, but the app-lifetime `AudioServiceConfig` is created before `runApp`.
Its Android notification channel name, description, and media-error message
therefore remain stable English strings. Platform secure-storage item labels are
also configured before a Flutter localization context exists. Native window
titles and application labels intentionally keep the untranslated `fura music`
brand.

**Why accepted:** Moving locale selection ahead of playback-service startup
would couple presentation settings to the system-media owner and could recreate
the Android lifecycle defect fixed by the app-scoped playback host. The current
strings do not alter playback, account, Queue, or Provider behavior, and release
identity localization has not been authorized.

**Impact:** First-party Flutter UI follows the selected language, while Android
system settings may continue to show an English playback-channel description.
The product name remains consistent across native shells.

**Risk:** A user may see mixed-language copy outside Flutter. A future attempt
to localize it could accidentally initialize a second AudioService handler or
replace the active playback owner during a language change.

**Suggested solution:** When native metadata localization is authorized, resolve
the persisted effective locale once before the single AudioService
initialization and load the corresponding generated catalog without a
`BuildContext`. Keep one handler for the full app lifetime; changing language
must not recreate it. Use platform-native resource catalogs only where release
identity requirements justify them.

**Trigger condition:** Reassess before localized release metadata is required,
when notification-channel copy becomes a product acceptance criterion, or when
the playback plugin exposes a safe in-place localized metadata update.

## TD-013 — NetEase official login inherits Linux WebKitGTK risk

**Status:** Resolved for the Linux login route by HD-029; cross-platform plugin
packaging and non-Linux WebView evidence remain open

**Problem:** HD-027's pinned `webview_all 1.4.1` candidate provides a common
visible WebView, native HttpOnly Cookie access and deterministic session close,
but its Linux implementation still runs on WebKitGTK 4.1. The earlier embedded
candidate produced Human-observed EGL/DMABuf and GStreamer WebProcess failures.
A 50-cycle machine soak passing on one Wayland/NVIDIA+AMD host cannot erase
that runtime evidence or establish broad hardware/driver stability.

**Why accepted:** The HD-027 trial was bounded and preserved direct/external QR
rollback. Later Human evidence showed that the initial default-renderer probe
was not representative: the actual product route stayed blank while WebKitGTK
repeatedly failed DMA-BUF EGL imports. A controlled SHM A/B restored initial
rendering, but the strict actual-page soak crashed `WebKitWebProcess` after 17
completed loads. HD-028 then reproduced the same process, signal, crash thread
and NVIDIA EGL library class through isolated Tauri/Wry after the third SHM
page finish. The candidate is therefore evidence-rejected rather than accepted
for production, and switching Flutter WebView wrappers cannot address the
measured fatal path.

**Impact:** The rejected WebKitGTK runtime is no longer selected for Linux
official login. The `webview_all` dependency remains for non-Linux platforms,
whose runtime acceptance is independent; its current cross-platform package
may still retain WebKitGTK build/runtime dependencies in Linux artifacts even
though Fura does not create that session there. Linux now adds target-scoped
CDP/process dependencies but no bundled browser runtime.

**Risk:** Flutter's default transport produces a blank page and continuous
DMA-BUF import failures. Tauri default did render and complete 12 strict cycles,
but attempt 13 timed out rather than reaching the required 100/100. Forced SHM
reached SIGSEGV in NVIDIA EGL on WebKit's `SkiaGPUWorker` through both Flutter
and Tauri hosts. Real security-verification pages, long-lived sessions, another
compositor or another GPU/driver add more unknowns. Shipping either observed
WebKit path would expose users to a broken login or process loss.

**Suggested solution:** Implemented by HD-029 as a Fura-owned disposable
profile in the installed system Chromium-family browser, with loopback-only
ephemeral CDP, exact Cookie minimization, Rust verification, and required
cleanup. Keep external QR as rollback. Do not restore WebKitGTK on Linux or
stack renderer flags on the current build.

**Trigger condition:** Reopen the Linux portion if Human login/cancel/restore
acceptance fails, browser/CDP policy changes, cleanup leaves an owned profile,
or a supported Linux package lacks an acceptable native Chrome/Chromium binary.
Reassess non-Linux WebView behavior separately before claiming those platforms;
remove the unused Linux plugin edge only when Flutter dependency packaging can
do so without deleting the retained non-Linux route.

## TD-014 — Long Roam sessions retain every appended Queue entry

**Status:** Open

**Problem:** HD-035 appends each bounded Related Tracks batch to the one public
Rust Queue so Queue order, current position and user actions remain truthful.
An unusually long uninterrupted Roam session can therefore retain an increasing
number of already completed entries in memory.

**Why accepted:** The current Queue deliberately has no entry provenance,
automatic-retention policy or hidden recommendation buffer. Removing completed
entries would change visible Queue history and positional semantics; inventing a
Roam-origin framework or second Queue would exceed the accepted playback model.
Each terminal request and appended batch is already bounded.

**Impact:** Normal sessions remain simple and inspectable, while an extreme
continuous Roam session may grow the public Queue until the user clears or
replaces it.

**Risk:** Sustained unattended playback could accumulate avoidable memory and
make Queue presentation increasingly large. An unsafe compaction could instead
delete user-added duplicates, invalidate the current position, or race a late
continuation result.

**Suggested solution:** Only after product authority defines which entries may
be retired, add explicit Queue provenance and a bounded retention rule inside
Rust. Preserve user-added entries and duplicates, current/next semantics,
generation cancellation and one atomic public snapshot; do not hide overflow in
a second Dart Queue.

**Trigger condition:** Reassess after a measured long-session memory/Queue
problem, before a user-facing persistent Roam control is accepted, or when a
separate Human Decision defines Queue provenance and retention behavior.

Each future item must record: ID, status, problem, why accepted, impact, risk, suggested solution, and trigger condition. Source TODOs should reference the corresponding ID where practical.
