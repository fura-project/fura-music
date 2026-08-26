# M4 Post-Playback Global Ranking — 2026-08-27

## Trigger

The finite Queue and Expanded Now Playing hierarchy slices completed, so autonomous execution returned to whole-project ranking before any further presentation change.

## Evidence review

- Strict Dart checks, all 308 Flutter tests, 267 offline Rust tests, strict all-target Clippy, Linux x64 Release, and packaged typed-Bridge integration pass. No new playback, credential, Provider, Bridge, navigation, data-safety, or platform correctness failure appeared.
- M1 still needs one user-operated real-account playback → queue → synchronized/word-timed lyric observation. That local evidence gap cannot be closed by reading stored credentials or by offline tests.
- Queue and Expanded Now Playing now have deliberate compact/desktop information hierarchy while preserving one Rust positional Queue, one foreground playback owner, and one lyric controller path.
- Lyrics already has exact loading/unavailable/error/authentication/content states, isolated live announcements, recovery actions, line seek, word timing, follow suspension/resume, compact sheet, wide dialog, and inline expanded presentation regressions. No reproduced gap currently justifies another M4.5 implementation.
- M4.6 explicitly authorizes a bounded matrix review across width, resize, light/dark, keyboard, pointer, touch, focus, and content states. The baseline has changed across eleven M4 slices, so reviewing the integrated product now has more value than another local visual edit.

## Ranked candidates

### 1. M4.6 cross-platform product audit — selected

- **Provenance:** M4.6 and M4 exit criteria 1–7.
- **User value:** identify any remaining integrated Material, adaptive, accessibility, or state-language gap before checkpoint work instead of polishing whichever file is easiest to inspect.
- **Current problem:** individual slices have focused compact/wide regressions, but the resulting eleven-slice baseline has not yet received one bounded whole-product matrix review.
- **Scope:** audit Theme, App Shell, Authentication, Library, Playlist, Search, Discover, Album, Artist, Now Playing, Queue, and Lyrics across 360 px, medium, desktop, resize, light/dark, keyboard, pointer/touch, focus/return, and loading/empty/error/retry/selected/playing evidence; inspect existing implementation and tests without live QQ or credentials.
- **Acceptance criteria:** record evidence and exact coverage limits; produce at most three candidates with provenance, user value, concrete problem, finite scope, acceptance criteria, effort, risk, and non-goals; select only an evidenced task or record that no implementation is justified.
- **Effort:** Discovery.
- **Risk:** the broad matrix could become an unbounded screenshot or micro-polish exercise.
- **Explicit non-goals:** page rewrites, new features, pixel-perfect goldens, theme personas, protocol/Domain/Bridge/Rust changes, real-account automation, or treating absent platform hardware as failed evidence.

### 2. Lyrics state-language alignment — deferred

- **Provenance:** M4.5 and M4 exit criteria 1 and 4.
- **User value:** a demonstrated mismatch could make lyric recovery more predictable.
- **Ranking reason:** no current correctness, reachability, semantics, or state-recovery failure is reproduced; the private live-region boundary is intentional.
- **Effort:** Medium if evidence appears.
- **Risk:** accessibility regression from duplicate announcements or recovery controls entering a live region.
- **Explicit non-goals:** implementation based only on visual similarity to shared catalog panels.

## Selection

M4.6 cross-platform product audit is the highest-value legal task. It ranks the integrated baseline before any further implementation and prevents local presentation work from outrunning evidence.
