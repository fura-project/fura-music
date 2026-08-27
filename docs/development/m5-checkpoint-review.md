# M5 Mainstream QQ Music Product Experience & Core Feature Completion Checkpoint — 2026-08-27

## Outcome

M5 is checkpoint-ready within the accepted Home-first first-release scope. Seven bounded phases now provide a truthful authenticated Home; retained Discover, Search, and Library destinations; coherent Playlists/Albums/Artists Library sections; Rust-authoritative sequential/shuffle and repeat modes; read-only Track comments; one exact Track-associated MV journey; and consistent Album/Artist context from validated Track data.

This checkpoint is not project completion, release readiness, live QQ compatibility approval, or authorization for another product category. It does not close M1: corrected authenticated media resolution → foreground playback → Queue navigation → synchronized/word-timed lyrics still requires one coarse user-operated observation.

## Exit-criteria evidence

1. **Useful truthful Home — Pass.** Authenticated startup and verified credential restore enter a small Home whose actions route only to the existing Discover, Search, and Library capabilities. It neither duplicates Discover nor claims a personalized heterogeneous feed.
2. **Predictable retained primary destinations — Pass.** Home, Discover, Search, and Library are explicit peers in compact `NavigationBar` and desktop `NavigationRail` presentation. Search and Discover controllers stay mounted across destination/width changes, local overlays return to their exact origins, primary back returns to Home, and the single Now Playing owner remains outside destination churn.
3. **Coherent Library sections — Pass.** Playlists, favorite Albums, and favorite Artists are direct adaptive sections. Favorite controllers initialize only on first visit and then retain paging, errors, detail routes, and loaded state; back unwinds detail → originating section → Playlists → Home.
4. **Authoritative playback modes — Pass.** `music-domain::PlaybackQueue` owns sequential/shuffle order and repeat off/all/one, including completion, wrap, duplicate-position, selection, and mutation repair. The Bridge exposes typed state/commands, Flutter does not infer traversal, and compact/expanded accessible controls reuse the existing playback owner.
5. **Bounded read-only comments — Pass within offline evidence.** A provider-neutral comment Domain/capability, direct bounded QQ client operation, Provider mapping, cancellable Bridge handle, and adaptive Now Playing surface cover first/empty/error/retry/append/cancel/stale/disposal behavior without mutation or a social framework. Two current independent implementations support the request shape; this checkpoint does not claim live application compatibility or content quality.
6. **Bounded Track-associated MV — Pass within current evidence.** Current independent implementations support the exact Track detail → optional VID → metadata/source path. Provider-neutral Domain/capability and a cancellable Bridge feed one disposable MV-only Flutter session from Expanded Now Playing. Music remains the Queue owner, foreground audio/video arbitration is explicit, and no MV Search/Discover, related-video, fullscreen/PiP, download, cache, or generic video platform was added. Packaged Linux synthetic H.264 decode/control and earlier Android x64 packaging pass; live QQ source availability, remote playback, hardware decode, and unavailable targets remain unproved.
7. **Existing journeys do not regress — Pass.** The 336-test Flutter suite covers authenticated Home/shell, retained Search/Discover/Library/detail routes, adaptive Track rows, playback/Queue/modes, comments, MV presentation, synchronized lyrics, failures, stale suppression, focus, and compact reachability. M5.6 additionally proves keyboard/tap shared Track context, exact collaboration selection, menu omission without usable context, unchanged play/Queue actions, and Radar → Album → Radar retention.
8. **Flutter/Rust boundary — Pass.** QQ request construction, credential rules, opaque identity parsing, Provider mapping, playback-mode semantics, comments mapping, MV correlation/source selection, and lyrics parsing/timing remain in Rust. Flutter owns Home/shell composition, retained routes, Material controls, focus/semantics, short-lived controllers, and native playback adapter lifecycle. Static scans found no QQ operation names in handwritten Dart and no Flutter/Material dependencies in Rust Core.
9. **No unapproved expansion — Pass.** M5 added no Provider, sidecar, download platform, mutation, background-playback lifecycle, persistent history, state/navigation framework, theme persona, plugin runtime, or speculative generic catalog/social/video abstraction. The only new playback dependency is the bounded MV-only native stack accepted for M5.5 and tracked for release notices by TD-006.
10. **Validation baseline — Pass.** The current checkout passes Rust formatting, 297 offline Rust tests, strict all-target Clippy, strict Dart formatting/analysis, all 336 Flutter tests, Linux x64 Release, packaged Linux typed Bridge, disposable non-account vault, local-file/loopback MP3, and synthetic local-H.264 MV integrations. Four live QQ/WeChat Rust tests remain explicitly gated and ignored.
11. **Complete classified audit — Pass.** `m5-product-completeness-audit.md` assigns every material remaining first-release gap to agent-authorized, evidence-blocked, environment-blocked, human-decision, or out-of-scope work. Its sole evidenced authorized implementation gap—inconsistent shared Track Album/Artist context—is resolved. Re-review found no additional untracked high-value M5 code task.

## Architecture and scope review

- Home is a presentation-only default over stable journeys; it does not own Provider aggregation, personalization, or a second copy of Discover state.
- The retained `UserLibraryPage` tree remains intentionally local because it preserves loaded destination, collection, detail, focus, and playback state. No navigation or state-management replacement was introduced.
- One Rust positional Queue remains authoritative. One Flutter music coordinator owns resolution/audio/Queue/lyrics, while each MV surface owns one disposable video session that yields to later music activation. Comments and MV cannot replace navigation, Queue, credentials, or lyrics.
- Raw QQ response values stop in `QQMusicClient`; `QQMusicProvider` maps provider-neutral values; the Bridge remains typed, coarse, cancellable, and free of product business rules.
- Shared Track context uses only existing validated Album/Artist values and retained route callbacks. It does not parse opaque identity, add a Track-details model, or change queue semantics.
- Only QQ Music exists as a Provider. Source scans found no handwritten TODO/FIXME/HACK marker, and Git tracks no APK/AAB, build/target output, keystore, signing artifact, or `.dart_tool` output.

## Adaptive and accessibility review

- Direct regressions cover 360 px Home/navigation, Library sections, Discover/Search selectors, shared dense Track context, playback modes, Now Playing, comments, MV, Queue, lyrics, failure recovery, and no-overflow paths. Desktop tests cover NavigationRail, dense rows, dialogs, keyboard traversal/actions, pointer behavior, shortcuts, and focus return.
- M5.6's official Material popup remains absent when no valid destination exists, is reachable by Tab/Enter and touch, represents every credited Artist explicitly, and preserves the direct Queue action. Retained navigation returns without reloading the origin.
- Current evidence is automated widget/integration coverage on this Linux environment plus previously recorded Android x64 packaging/emulator evidence. It is not manual visual or assistive-technology approval across every DPI, font renderer, compositor, physical device, or unavailable platform.

## Technical debt and Human Decisions

- **TD-001 — Open:** localized system-Cargo Linux/Linux-host Android paths remain bounded and passing; M5 did not change FRB generation or add another ABI.
- **TD-002 — Triggered, blocked by HD-001:** generated identity/development signing remains unsuitable for distribution. No artifact was published.
- **TD-003 — Resolved:** M5 did not weaken server-verified credential restore or account replacement.
- **TD-004 — In Progress:** Linux and Android x64 vault instances remain proven; Apple/Windows runtime evidence remains unavailable.
- **TD-005 — Open:** no sanitized evidence reached the favorite-playlist 1,000-row ceiling.
- **TD-006 — Open, release-triggered:** the native MV stack needs exact per-artifact license/notice review before distribution; it does not block development while HD-001 remains pending.
- **HD-001 — Pending, locally scoped:** final name, identifiers, signing custody, and distribution remain blocked.
- **HD-002/HD-003 — Accepted:** M5 preserved the default Material baseline and implemented the authorized Home-first mainstream scope without anticipating deferred focus/theme infrastructure.

No debt trigger changed during M5.6/M5.7 and no new Human Decision is required to checkpoint the implemented scope.

## Validation boundaries

The checkpoint proves current offline rules, Flutter presentation/state regressions, Linux native adapters, packaged in-process Bridge, and Linux buildability on this checkout. The disposable vault test touched only one randomized non-account key and verified cleanup. No stored credential, account endpoint, live QQ operation, remote media source, user content, or secret-bearing fixture was used.

It does not prove current live comments/MV availability, authenticated QQ CDN playback/seek, physical Android audio focus or hardware video decode, Apple/Windows runtime, every desktop environment, production signing/notices, or M1 end-to-end acceptance. Earlier Android x64/translated ARM64 evidence remains bounded to the exact artifacts and environments recorded in project state.

## Post-checkpoint scheduling

Checkpoint completion returns to whole-project ranking. Remaining items must retain their classified authority: the M1 observation is user-operated; live comments/MV compatibility needs bounded secret-safe evidence; unavailable targets need their real environments; release work needs HD-001 and TD-006 handling; offline/cache/fallback direction needs demonstrated value and Roadmap authority. Deferred or out-of-scope ideas do not become tasks merely because M5 checkpointed. `M5 checkpoint != project complete` and `global_stop` remains false.
