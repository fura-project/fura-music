# M3 QQ Music Core Product Discovery — 2026-08-26

## Evidence boundary

- L-1124/QQMusicApi commit `108617ffe80abefec6358717b9f4d3677550db10` (2026-08-05) uses `music.search.SearchCgiService` with the mobile typed-search method and explicit page metadata.
- feeluown-qqmusic commit `241a9678bcd26e88d19e08e5da8048018f06e330` (2026-03-26) independently uses the same service with `DoSearchForQQMusicDesktop` and maps song, artist, album, playlist, and MV result containers.
- A bounded anonymous request to the real `musicu.fcg` Desktop method returned global/module code `0`, five requested song rows, current page `1`, next page `2`, and a numeric total. Only those coarse values and response field names were observed; no account material, song content, identifier, URL, or full response was retained.
- The observed song row contains the same minimum identity/display fields already required by this repository's playlist-detail mapping: numeric ID, song MID/type, file media MID, title, singers, album, duration, and file sizes.

Reference implementations are research evidence only; no third-party runtime service or source model becomes a project dependency.

## Ranked candidates

### 1. Track search vertical slice — selected

- Provenance: `ROADMAP.md` M3 Search direction plus cross-validated protocol and bounded anonymous behavior.
- User value: users can find and play QQ Music tracks outside their existing playlists, the largest missing core-client entry flow.
- Problem: the authenticated product surface currently exposes only the user's playlists and has no catalog entry point.
- Scope: provider-neutral paged Track search, direct QQ Music protocol mapping, thin cancellable Bridge operation, adaptive Flutter search/result states, pagination, and playback through the existing queue.
- Acceptance: a nonblank query can load, replace, cancel, retry, paginate, show empty/error states, and start or queue a result; stale queries cannot replace current results; offline tests cover protocol, mapping, cancellation, controller lifecycle, and primary UI flow.
- Effort: medium-high.
- Risk: medium; protocol response shape and pagination are external, and search must not leak raw QQ models into Flutter.
- Non-goals: artist/album/playlist result types, suggestions, hot-search, search history, ranking personalization, new audio quality selection, or a navigation framework.

### 2. Album and Artist browsing — deferred

- Provenance: `ROADMAP.md` M3 Album and Artist direction.
- User value: completes catalog exploration after a user discovers a track or entity.
- Problem: no current product entry point reaches an album or artist identity.
- Scope: one entity type at a time with an evidenced detail RPC and paged Track mapping.
- Acceptance: entity summary to detail to existing playback queue with truthful empty/error/pagination states.
- Effort: high.
- Risk: medium-high because two new identity/detail models are possible and Search is the natural prerequisite.
- Non-goals: implementing both entity types together, biographies, comments, MV, or unrelated recommendations.

### 3. QQ Music Home and recommendations — deferred

- Provenance: `ROADMAP.md` M3 evidence-backed Home/recommendation direction.
- User value: improves everyday discovery and gives the client a content-driven landing surface.
- Problem: the current landing surface is library-only.
- Scope: one observed QQ-native section at a time after response/refresh semantics are established.
- Acceptance: stable section identity, truthful refresh/failure behavior, Domain mapping, and a bounded user action.
- Effort: high.
- Risk: high because section composition, personalization, and protocol shape are more volatile than typed Search.
- Non-goals: reproducing the entire official homepage, recommendation algorithms, or speculative section abstractions.

## Selection

Track search ranks first because it has the strongest current protocol evidence, highest immediate user value, and a finite path into the existing playback queue. Album/Artist and Home remain authorized M3 directions, not implementation commitments for this slice.
