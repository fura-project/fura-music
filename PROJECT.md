# Project

## Why

QQ Music users should have an open, modern, cross-platform client whose core music logic is reusable and whose failure modes do not depend on a separately operated third-party API server.

## Target users

- QQ Music listeners who want a high-quality desktop experience without giving up first-class mobile use.
- Open-source contributors who need explicit product and architecture boundaries.

## Product positioning

`flutterustmusic` is a QQ Music-first client, not a multi-service aggregation dashboard. QQ Music is the first-class provider. Other providers may later supply local media or narrowly scoped fallback capabilities when a real product need exists.

## Core experience

- Sign in to QQ Music and restore the session safely.
- Browse the user's playlists and their tracks.
- Resolve and play music with a reliable queue.
- Present an immersive now-playing view and an excellent lyric experience, including basic word-level timing.
- Behave as a deliberate Material 3 music product on desktop and mobile.

## Product boundaries

- Flutter owns widgets, navigation, adaptive layout, animation, presentation state, and short-lived interaction state.
- Rust owns reusable music domain logic, QQ Music protocol behavior, credentials, providers, identity, media resolution, lyrics, storage policy, and other long-lived business rules.
- Flutter and Rust run in the same application process through a thin typed bridge.
- Providers return capabilities and domain data; they do not supply application UI.
- Runtime operation must not depend on a localhost or hosted third-party QQ Music API sidecar.

## Non-goals

Without an explicit human product decision, this project will not become:

- a broad QQ Music, NetEase Cloud Music, Spotify, or YouTube Music aggregator;
- a podcast client, social network, generic media center, or download-tool collection;
- a dynamic plugin marketplace or arbitrary-code plugin runtime.

## Long-term direction

Prove the complete QQ Music vertical slice first. Extend capability only from demonstrated user needs, keep provider differences explicit, and prefer measurable correctness and reliability over speculative extensibility.

Changes to this document's product definition require an entry in `HUMAN_DECISIONS.md`.
