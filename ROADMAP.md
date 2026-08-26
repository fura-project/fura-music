# Roadmap

## Current Milestone — M1 First QQ Music Vertical Slice

### Goal

Deliver the smallest coherent user journey from QQ Music sign-in through word-level lyrics while proving the in-process Flutter/Rust architecture.

### Progressive phases

1. **Executable foundation** — governance, Flutter/Rust workspaces, thin typed bridge, minimum domain/provider boundaries, QQ Music client seam, and offline tests.
2. **Authentication** — login flow, credential state, safe persistence boundary, and restore behavior.
3. **User library** — user playlists and playlist details backed by real QQ Music behavior and sanitized fixtures or repeatable integration evidence.
4. **Playback** — media resolution, playback, and queue behavior.
5. **Lyrics** — lyric loading, QRC parsing, and basic word-level presentation.

### Acceptance criteria

- A user can complete sign-in, restart the app, and regain the appropriate credential state.
- The user can browse their playlists, open one, start a playable track, and manage the queue.
- Synchronized lyrics and a basic word-level lyric experience work for supported tracks.
- Flutter and Rust remain in one process with a thin typed boundary.
- QQ Music protocol and mapping behavior has offline regression coverage; live integration tests are separate.
- Linux desktop and at least one mobile target build successfully before the milestone checkpoint.
- No runtime third-party QQ Music API server or unapproved provider expansion exists.

### Dependencies

- Verified QQ Music protocol behavior from real responses, repeatable integration tests, or cross-validation across independent active implementations.
- A platform-safe credential storage approach before any public alpha.

## Next Milestone — M2 Reliability and Daily-Use Quality

Scope is progressively elaborated only around current evidence. A remaining M1 acceptance observation does not globally block independent M2 work and does not become implicitly satisfied by that work. Expected themes are failure recovery, adaptive desktop/mobile polish, playback resilience, cache policy, accessibility, and packaging. The first bounded slice covered desktop transport ergonomics and compact now-playing polish: shared keyboard controls, truthful progress/seeking, session-local volume, and existing Track artwork. The second bounded interaction slice exposed only existing playback/queue capabilities through adaptive Track context actions, retained duplicate positional intent in the Rust queue, kept shared transport shortcuts active while queue, lyric, or volume modal routes own focus, made queue-result feedback independent from a first Track's slower media startup, and protected the destructive queue clear command with a confirmation boundary. A first authentication-hygiene slice added ordered local sign-out with explicit Core/vault failure semantics, immediate playback stop, single-flight cleanup retry, and explicit retry progress without inventing a remote logout protocol. Both destructive confirmations now use reachable bottom sheets below 600 logical pixels and dialogs on wider windows. A first accessibility slice removed reproduced duplicate screen-reader metadata from playlist and Track actions while preserving tap and mobile long press, removed the non-interactive shortcut focus node from traversal, isolated meaningful now-playing and queue-failure state changes in live regions, and stopped the non-actionable current queue row from advertising a button/tap while preserving selection. A subsequent album-art-driven queue slice reused the same provider-neutral Track artwork, kept local loading/error fallbacks, and retained an unambiguous current-position overlay without changing queue semantics. The first daily lyric slice now follows active lines, yields to manual scrolling, restores follow explicitly, and seeks through exact line timing only while the existing playback controller allows it; no playback state moved into the lyric controller. Further M2 slices remain progressively selected from demonstrated gaps. This is not authorization for new providers or unrelated product features.

## Later direction

Only after the QQ Music experience is coherent should the project evaluate narrowly scoped local-library or media-fallback capabilities. Each expansion requires demonstrated user value and must preserve the QQ Music-first product identity.
