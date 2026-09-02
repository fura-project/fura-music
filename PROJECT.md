# Project

## Why

QQ Music users should have an open, modern, cross-platform client whose core music logic is reusable and whose failure modes do not depend on a separately operated third-party API server.

## Target users

- QQ Music listeners who want a high-quality desktop experience without giving up first-class mobile use.
- Open-source contributors who need explicit product and architecture boundaries.

## Product positioning

`fura music` is a QQ Music-first client, not a multi-service aggregation dashboard. QQ Music is the first-class provider. Other providers may later supply local media or narrowly scoped fallback capabilities when a real product need exists. The repository and internal package names may remain `flutterustmusic`; they are implementation identifiers rather than the product display name.

## Core experience

- Sign in to QQ Music and restore the session safely.
- Start from a useful, bounded Home that connects QQ Music discovery, Search, and the user's Library without pretending to be an uncontrolled personalized feed.
- Browse QQ Music catalog and recommendation surfaces, Search, and the user's playlists, favorite Albums, and favorite Artists through clear first-class destinations.
- Resolve and play music with a reliable queue and familiar playback modes.
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

Complete a mainstream, Home-first QQ Music product experience over the proven vertical slice while keeping Library, Discover, Search, playback, and Now Playing coherent and independently truthful. Extend capability only from demonstrated user needs or an accepted product decision, keep provider differences explicit, and prefer measurable correctness and reliability over speculative extensibility. A later focused or quiet experience may be evaluated as a separate product phase; it is not part of the first-release baseline.

Changes to this document's product definition require an entry in `HUMAN_DECISIONS.md`.
