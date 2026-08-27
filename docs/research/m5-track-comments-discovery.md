# M5.4 Bounded Discovery — Track Context and Read-only Comments

## Boundary

This pass audited the current Track row, mini-player, expanded Now Playing, Queue, lyrics, Album/Artist navigation, playback availability and mode presentation, plus current external comment implementations. It did not call QQ Music, access stored credentials, capture a real response, authorize comment mutation, add MV behavior, or create a generic Track-detail/navigation framework.

## Existing product context

The active Track already has one authoritative playback/Queue/lyric path. Expanded Now Playing retains that path and exposes artwork, title, credited Artists, Album metadata, synchronized lyrics, playback progress, transport, Queue, volume, shuffle, and repeat. Existing catalog callbacks open validated Album and Artist identities without parsing QQ-specific Track identity in Flutter. Playback resolution failures already remain isolated in the existing player state.

The concrete M5.4 gap is therefore read-only song comments. It is not a missing root destination or permission to add a large action menu to every Track row. The least disruptive entry is a secondary action in expanded Now Playing, presented in an adaptive modal surface so closing it returns to the same retained Now Playing and playback owner.

## Protocol evidence

Three current source snapshots were inspected without executing their QQ requests:

- `feeluown/feeluown-qqmusic` commit `241a9678bcd26e88d19e08e5da8048018f06e330` (2026-03-26) calls `fcg_global_comment_h5.fcg` with `biztype=1`, `cmd=8`, a numeric song identity, zero-based `pagenum`, and bounded `pagesize`. It maps the returned hot-comment author name, comment ID, text, praise count, and Unix time into its provider-neutral comment model.
- `Yyyangshenghao/simple-music` commit `301d1ca159e88f6226acbc95fb01a28a99234e79` (2026-08-23) independently uses the same legacy operation and parameters, falls back from MID to numeric song identity before the request, maps the same author/text/time/praise fields, reads `comment.commenttotal`, and pages newest comments by `pagenum`. It treats `hot_comment.commentlist` as a separate first-page collection.
- `L-1124/QQMusicApi` commit `108617ffe80abefec6358717b9f4d3677550db10` (2026-08-05) uses the newer `music.globalComment.CommentRead` service and independently confirms the product semantics and common fields for hot/new lists: comment/sequence identity, nickname, avatar, content, publish time, praise count, reply count, total, and continuation. Its exact cursor request is not selected because no second current implementation of that request shape was established in this pass.

The two independent current legacy implementations establish the selected request shape without a live account probe. They also show that basic read access does not require application access to stored account credentials. Offline fixtures for this repository must remain synthetic and content-safe; until a bounded live test is separately run, compatibility with the service at runtime remains unproven and failures must stay truthful and retryable.

## Minimum provider-neutral model

The first slice needs only:

- provider-scoped opaque comment identity;
- author display name;
- comment text;
- publish time in Unix seconds;
- praise count;
- one page containing a separate hot collection, newest collection, total newest count, offset, and continuation.

Avatar, encrypted user identity, reply bodies, reply summary, badges, hashtags, media attachments, recommendation scores, and account-specific praised/self flags are omitted. The selected legacy sources do not jointly establish all of those fields, and they are not required to deliver safe read-only browsing.

## Ranked candidates

### 1. One legacy request with first-page hot and paged newest comments

**Provenance:** HD-003; M5 phase M5.4 and exit criteria 6, 10, 11, 14, and 15.

**User value:** From the currently playing Track, the user can read the most relevant discussion and continue through recent comments without leaving or disrupting playback.

**Current problem:** No comment Domain, Provider, Bridge, controller, or presentation path exists. Album/Artist, lyrics, Queue, and playback-mode context are already reachable, so a generic Track-detail rewrite would add risk without solving a broader evidenced gap.

**Scope:** Add a small provider-neutral comment page and Provider capability; implement the cross-validated anonymous legacy request in `QQMusicClient`; keep numeric Track identity parsing in `QQMusicProvider`; add one cancellable coarse Bridge load; add a Dart gateway/controller with explicit initial, empty, retry, append, cancellation, stale, and disposal handling; and open an adaptive comments surface from expanded Now Playing.

**Acceptance criteria:**

- Synthetic offline fixtures prove exact request shape, bounded inputs/body, separate hot/new mapping, text/identity bounds, total-derived continuation, empty pages, malformed rows, HTTP/service/JSON failures, and content-free diagnostics.
- QQ-specific numeric Track identity never crosses the Provider boundary, while the Bridge and Flutter use only provider/opaque Track identity and provider-neutral comment values.
- First load shows hot and newest sections independently; pagination appends only newest comments, deduplicates provider/opaque comment identity, and exposes an isolated append retry.
- Cancellation, replacement, disposal, empty, initial failure, append failure, and stale completion are explicit and have regressions.
- The comments surface is reachable by keyboard, pointer, and touch from expanded Now Playing; 360 px and wide layouts do not overflow; closing it preserves the current Track, Queue, lyrics, position controller, and prior page.
- Comment failure never changes playback, Queue, lyrics, credential, or navigation state. The relevant Rust/Bridge/Dart/widget tests and repository gates pass.

**Effort:** High but bounded.

**Major risks:** The unofficial legacy response may drift; malformed user-generated text could create excessive layout/resource use; total-based pagination can loop if zero-row pages are not terminal; a modal could obscure or duplicate playback ownership; generated Bridge bindings can drift.

**Explicit non-goals:** Posting, deleting, liking, replying, reporting, following users, reply threads, avatars, rich comment media, moment/recommended comment feeds, comment search, comments on every Track row, comment caching, stored recent history, MV, a generic Track-detail framework, or live account probing.

### 2. New musicu hot/new comment operations with cursor continuation

**Provenance:** M5.4 authorizes the product capability, but the exact protocol is currently evidence-blocked.

**User value:** The newer operation exposes an explicit continuation signal and richer reply metadata.

**Current problem:** Only one current source was found for the exact request and cursor fields. Implementing it now would violate the repository's critical QQ protocol evidence rule.

**Scope:** Deferred source/fixture discovery only; no endpoint implementation in this slice.

**Acceptance criteria:** A second independent current implementation, a sanitized real fixture, or a repeatable gated integration result establishes the exact request and response behavior.

**Effort:** Medium after evidence exists.

**Major risk:** Guessing a newer request would create a brittle protocol path and encourage expanding into unsupported comment subtypes.

**Explicit non-goals:** No implementation is selected from this candidate.

### 3. Generic Track action/detail framework before comments

**Provenance:** None sufficient for implementation; retained only as a rejected comparison.

**User value:** A shared framework could eventually hold Album, Artists, comments, MV, and other actions.

**Current problem:** Existing Album/Artist navigation, Queue, lyrics, availability, and playback-mode behavior already work through focused surfaces. MV has its own later evidence/discovery phase. Building a framework now would be speculative and could destabilize retained navigation.

**Effort:** High.

**Major risk:** Action clutter, navigation/state rewrite, duplicate playback surfaces, and an abstraction shaped by only one new capability.

**Explicit non-goals:** This candidate is rejected and does not authorize navigation or state-management changes.

## Selection

Candidate 1 ranks first. It delivers the explicit M5.4 user journey using two current independent protocol implementations, keeps the model deliberately smaller than the raw responses, and fits the existing retained Now Playing architecture. Candidate 2 remains evidence-blocked; candidate 3 is speculative and rejected.
