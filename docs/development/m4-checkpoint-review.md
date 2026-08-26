# M4 Deliberate Material 3 Product Experience Checkpoint — 2026-08-27

## Outcome

M4 is checkpoint-ready within its authorized default-Material scope. Twelve bounded slices now form one centralized light/dark theme, an adaptive retained application shell, shared music-information and state grammars, deliberate compact/desktop browsing, and a clearer Queue/expanded Now Playing hierarchy without replacing the existing navigation, state, playback, Provider, or Bridge architecture.

This checkpoint is not project completion, release readiness, manual visual approval on every platform, or authorization for deferred theme personas. It does not close M1: the corrected authenticated playback → queue → synchronized word-timed lyric observation still requires user operation.

## Exit-criteria evidence

1. **Coherent Material product language — Pass.** One official-Flutter light/dark theme defines bounded color, typography, shape, spacing, surface, motion, and component defaults. Authentication and the retained shell apply that foundation; catalog headers, dense Track tiles, secondary selectors, and loading/content-state panels provide shared grammar without erasing page-owned actions or failure semantics. Queue and Expanded Now Playing now follow the same metadata and action hierarchy.
2. **Deliberate desktop behavior — Pass.** The authenticated shell uses a labeled `NavigationRail` at wide widths; catalog and collection content has bounded width/list-grid strategy; Track rows retain music-appropriate density; Queue uses a dialog with a dedicated duration column; Expanded Now Playing uses a wide artwork/lyrics arrangement. Pointer context actions, desktop keyboard activation, shortcuts, focus return, and retained state have direct regressions.
3. **Compact/mobile reachability — Pass within current evidence.** The 360 px suite covers authentication, primary `NavigationBar`, saved-collection menu, every Search/Discover selector, Library/detail/catalog Track surfaces, Now Playing, Queue, Lyrics, loading/empty/error recovery, and no-overflow paths. Touch targets, semantic activation, long press, back behavior, and retained return remain intact.
4. **Existing ownership and accessible states — Pass.** Library, Search, Discover, Playlist, Album, Artist, saved collections, Now Playing, Queue, and Lyrics retain their existing controllers and local route ownership. Lazy retained primary destinations survive switching/resize; detail/collection return restores state and focus. Shared panels preserve page-specific retry/sign-in eligibility and one-live-region policy, while the single playback/queue/lyric coordinator remains authoritative.
5. **Flutter/Rust boundary — Pass.** Static scans found no handwritten Dart QQ operation names or QRC/media protocol implementation and no Rust Core Material/Widget dependency. QQ protocol, credential rules, Provider mapping, opaque identity, queue mutation, and lyric parsing/timing remain in Rust; Flutter owns theme, adaptive layout, local navigation, focus, semantics, animation, and short-lived controller state. The Bridge remains typed, coarse, cancellable, and provider-neutral.
6. **Validation baseline — Pass.** The current code passes strict Dart formatting and analysis, all 310 Flutter tests, Linux x64 Release, packaged Linux typed-Bridge integration, Rust formatting, 267 offline Rust tests, and strict all-target Clippy. Four live QQ/WeChat tests remain explicitly gated and ignored.
7. **No untracked high-value Material gap — Pass.** The bounded whole-product M4.6 audit found one reproduced cross-surface gap in favorite Album/Artist initial states; the twelfth slice closed it and added direct compact regressions. Post-fix ranking found no reproduced threshold, adaptive, accessibility, state, or hierarchy failure that justifies another implementation. Exact breakpoint matrices remain evidence-triggered rather than speculative.

## Architecture and scope review

- M4 changed presentation composition only. It added no QQ protocol or raw response model to Dart, no Flutter state to Rust, and no business rule to the Bridge.
- The retained `UserLibraryPage` local route/controller structure remains because it preserves loaded Search, Discover, collection, Album, Artist, Playlist, and playback state. No navigation or state-management framework was added.
- The existing foreground audio adapter, Rust positional queue, playback coordinator, and lyric controller remain the only owners. Expanded presentation reuses them rather than introducing a second player, progress timer, queue, or lyric path.
- Only the QQ Music Provider exists. No sidecar, third-party runtime QQ API server, local/fallback Provider, plugin runtime, download/social/MV/comment feature, heterogeneous Home feed, cache policy, or release system was introduced.
- No third-party Material 3 Expressive library, full custom M3E clone, theme persona, artwork-derived global palette, shader, blur system, visualizer, or speculative design-system framework was added.
- Fixed presentation colors are limited to the accepted theme seed and bounded black/white contrast overlays over QR/artwork imagery. Source scans found no handwritten TODO/FIXME/HACK marker. Git tracks no APK/AAB, build/target output, keystore, or signing artifact.

## Adaptive and accessibility review

- Representative compact, medium/wide, and compact-to-wide resize journeys pass. The exact 520/840 shell thresholds are not exhaustively parameterized because no boundary failure is reproduced; a future reachability, retention, or overflow failure remains sufficient provenance for a focused regression.
- Semantic labels, roles, explicit tap/long-press activation, logical keyboard entry, focus restoration, loading labels, and isolated failure live regions remain covered across the high-value paths changed by M4.
- Current evidence is automated layout/state coverage on the recorded Flutter/Linux environment, not manual screen-by-screen visual inspection across every font renderer, DPI, compositor, platform, or assistive technology.

## Technical debt and Human Decisions

- **TD-001 — Open:** current system-Cargo Linux and Linux-host Android paths remain bounded and passing; M4 did not regenerate or broaden the Bridge.
- **TD-002 — Triggered, locally blocked by HD-001:** development identity/signing remains unsuitable for distribution. No artifact was published and M4 does not broaden release authority.
- **TD-003 — Resolved:** presentation work did not weaken verified credential restore or account replacement.
- **TD-004 — In Progress:** Linux and Android x64 vault instances remain proven; Apple/Windows runtime evidence is still unavailable and cannot be inferred.
- **TD-005 — Open:** no sanitized account evidence reached the favorite-playlist safety ceiling.
- **HD-001 — Pending, locally scoped:** it blocks final identity/signing/distribution only.
- **HD-002 — Accepted:** M4 followed the authorized default-Material baseline and kept all named theme-persona work deferred.

No debt trigger changed and no new Human Decision is required.

## Validation boundaries

The checkpoint proves the current offline rules, Flutter presentation regressions, Linux build, and packaged in-process Bridge on this checkout. It does not prove live QQ catalog compatibility, authenticated QQ CDN playback/seek, recommendation quality, physical Android behavior, Apple/Windows runtime, every desktop compositor/DPI, release signing, or M1 end-to-end acceptance.

No stored credential, account endpoint, remote QQ media, live-test gate, or user-derived fixture was used for this review.

## Post-checkpoint scheduling

Checkpoint completion returns to whole-project ranking. The next selection must re-read the Roadmap's evidence-gated later direction, current user reports, risks, platform availability, and debt triggers. It must not infer authorization for theme personas, a new Provider, offline/cache policy, release work, or another product category. `M4 checkpoint != project complete` and `global_stop` remains false.
